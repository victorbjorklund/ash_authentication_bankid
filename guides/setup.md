# Setup Guide

This guide walks you through installing and configuring the BankID authentication strategy in your Phoenix application.

## Prerequisites

- Elixir 1.15+ 
- Phoenix 1.7+ with Ash Authentication
- BankID test or production certificate from Swedish BankID

## Step 1: Installation

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    # ... other deps
    {:ash_authentication_bankid, "~> 0.1.0"}
  ]
end
```

Install dependencies:

```bash
mix deps.get
```

## Step 2: Configure BankID Client

Add the BankID configuration to your `config/config.exs`:

```elixir
# config/config.exs
config :bankid, :client,
  # Test environment (BankID's test server)
  url: "https://appapi2.test.bankid.com/rp/v6.0",
  certificate: System.get_env("BANKID_CERT_PATH") || "path/to/test.certificate.pem",
  key: System.get_env("BANKID_KEY_PATH") || "path/to/test.key.pem",
  ca_file: System.get_env("BANKID_CA_PATH") || "path/to/test.ca.pem"

# For production, use the production URL:
# url: "https://appapi2.bankid.com/rp/v6.0"
```

### Environment Variables

For better security, use environment variables:

```bash
# .env
BANKID_CERT_PATH=/path/to/bankid/certificate.pem
BANKID_KEY_PATH=/path/to/bankid/key.pem  
BANKID_CA_PATH=/path/to/bankid/ca.pem
```

## Step 3: Create User Resource

Create or modify your user resource to support BankID:

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication]

  attributes do
    uuid_primary_key :id
    
    # BankID fields
    attribute :personal_number, :string, allow_nil?: false
    attribute :given_name, :string, allow_nil?: false
    attribute :surname, :string, allow_nil?: false
    attribute :bankid_verified_at, :utc_datetime_usec, allow_nil?: true
    attribute :ip_address, :string, allow_nil?: true
    
    # Standard user fields
    attribute :email, :string, allow_nil?: false
    attribute :password, :string, allow_nil?: true
  end

  postgres do
    table "users"
    repo MyApp.Repo
  end

  identities do
    identity :unique_personal_number, [:personal_number]
    identity :unique_email, [:email]
  end

  authentication do
    strategies do
      bank_id do
        order_resource MyApp.Accounts.BankIDOrder
        personal_number_field :personal_number
        given_name_field :given_name
        surname_field :surname
        verified_at_field :bankid_verified_at
        ip_address_field :ip_address
        
        # Optional customization
        order_ttl 300
        poll_interval 2000
        cleanup_interval 300_000
        consumed_order_ttl 86_400
      end
    end

    tokens do
      enabled? true
      token_resource MyApp.Accounts.Token
      signing_secret MyApp.Accounts.Secrets
    end
  end
end
```

## Step 4: Create BankID Order Resource

Create a resource to track authentication sessions:

```elixir
# lib/my_app/accounts/bank_id_order.ex
defmodule MyApp.Accounts.BankIDOrder do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :order_ref, :string, allow_nil?: false
    attribute :status, :atom, default: :pending, constraints: [one_of: [:pending, :complete, :failed, :consumed]]
    attribute :auto_start_token, :string, allow_nil?: false
    attribute :qr_start_token, :string, allow_nil?: true
    attribute :qr_start_secret, :string, allow_nil?: true, sensitive?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :consumed_at, :utc_datetime_usec, allow_nil?: true
    
    # Session binding for security
    attribute :session_id, :string, allow_nil?: false
    
    # Completion data
    attribute :completion_data, :map, allow_nil?: true
    attribute :ip_address, :string, allow_nil?: true
  end

  postgres do
    table "bank_id_orders"
    repo MyApp.Repo
  end

  identities do
    identity :unique_order_ref, [:order_ref]
  end

  actions do
    defaults [:read, :destroy]
    
    create :create do
      primary? true
      accept [:order_ref, :status, :auto_start_token, :qr_start_token, :qr_start_secret, :expires_at, :session_id, :ip_address]
    end
    
    update :complete do
      accept [:completion_data, :status, :consumed_at]
      require_atomic? false
    end
    
    update :mark_consumed do
      accept [:status, :consumed_at]
      require_atomic? false
    end
  end
end
```

## Step 5: Add Token Resource

If you don't already have a token resource:

```elixir
# lib/my_app/accounts/token.ex
defmodule MyApp.Accounts.Token do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  token do
    api MyApp.Accounts
  end

  postgres do
    table "tokens"
    repo MyApp.Repo
  end
end
```

## Step 6: Create Database Migrations

Generate and run migrations:

```bash
# Generate migrations
mix ash_postgres.generate_migrations --name add_users_and_bankid_orders

# Run migrations
mix ash_postgres.migrate
```

Review the generated migration files and adjust as needed.

## Step 7: Add Authentication Routes

Add authentication routes to your router:

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug AshAuthentication.Plug
  end

  scope "/auth", MyAppWeb do
    pipe_through [:browser, :auth]
    
    # These routes will be automatically generated by Ash Authentication
    # POST /auth/user/bank_id/initiate
    # GET /auth/user/bank_id/poll  
    # POST /auth/user/bank_id/renew
    # POST /auth/user/bank_id
  end

  # Your other routes...
end
```

## Step 8: Add Authentication Plug

Add the authentication plug to your endpoint:

```elixir
# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  @session_options [
    store: :cookie,
    key: "_my_app_key",
    signing_salt: "your_signing_salt",
    same_site: "Lax",
    # 7 days
    max_age: 7 * 24 * 60 * 60
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug MyAppWeb.Router
end
```

## Step 9: Test the Setup

You can test the setup using the installer task:

```bash
mix ash_authentication_bankid.install --test
```

This will generate a simple test page to verify your configuration works.

## Step 10: Frontend Integration

See the [Authentication Flows guide](authentication-flows.md) for detailed frontend integration examples.

## Troubleshooting

### Common Issues

#### Certificate Errors
```
** (BankID.Error) :certificate_err
```

**Solution**: Ensure your BankID certificates are correctly configured and accessible.

#### SSL/TLS Issues
```
** (BankID.Error) :internal_error
```

**Solution**: Check that your certificates are valid for the BankID API endpoints.

#### Database Connection Issues
```
** (DBConnection.ConnectionError) connection not available
```

**Solution**: Verify your PostgreSQL connection is working and migrations have been run.

#### Missing Fields Error
```
** (RuntimeError) Missing required field: personal_number
```

**Solution**: Ensure all required fields are present in your user resource and migrations.

### Debug Mode

Enable debug logging to troubleshoot issues:

```elixir
# config/dev.exs
config :logger, level: :debug
config :bankid, debug: true
```

### Test with BankID Test Server

Use BankID's test environment during development:

- Test users are available: [BankID Test Users](https://www.bankid.com/en/utvecklare/guider/test-av-bankid-i-testmiljo)
- Test certificates available from BankID's developer portal

## Next Steps

- [Authentication Flows](authentication-flows.md) - Learn about different authentication methods
- [API Reference](api.md) - Detailed API documentation  
- [Frontend Examples](frontend-examples.md) - Complete frontend implementations