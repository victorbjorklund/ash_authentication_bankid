# How-to Guides

This section contains practical guides for common implementation scenarios when using the BankID authentication strategy.

## Multi-Strategy Authentication

### Scenario: Support both BankID and Email/Password

Allow users to authenticate using either BankID or traditional email/password authentication.

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
    attribute :personal_number, :string, allow_nil?: true
    attribute :given_name, :string, allow_nil?: true
    attribute :surname, :string, allow_nil?: true
    attribute :bankid_verified_at, :utc_datetime_usec, allow_nil?: true
    
    # Email/password fields
    attribute :email, :string, allow_nil?: false
    attribute :hashed_password, :string, allow_nil?: true, sensitive?: true
    attribute :password_confirmation, :string, allow_nil?: true, sensitive?: true
  end

  authentication do
    strategies do
      # BankID strategy
      bank_id do
        order_resource MyApp.Accounts.BankIDOrder
        personal_number_field :personal_number
        given_name_field :given_name
        surname_field :surname
        verified_at_field :bankid_verified_at
      end

      # Password strategy
      password do
        identity_field :email
        hashed_password_field :hashed_password
        password_confirmation_field :password_confirmation
      end
    end

    tokens do
      enabled? true
      token_resource MyApp.Accounts.Token
      signing_secret MyApp.Accounts.Secrets
    end
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_personal_number, [:personal_number]
  end
end
```

### Frontend Implementation

```javascript
// Dual authentication interface
function AuthInterface() {
  const [authMethod, setAuthMethod] = useState('bankid');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleBankIDAuth = async () => {
    try {
      const bankIDClient = new BankIDClient('/api');
      const result = await bankIDClient.authenticate();
      // Handle successful BankID authentication
      localStorage.setItem('auth_token', result.access_token);
      window.location.href = '/dashboard';
    } catch (error) {
      console.error('BankID auth failed:', error);
    }
  };

  const handlePasswordAuth = async (e) => {
    e.preventDefault();
    try {
      const response = await fetch('/api/auth/user/password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      
      const result = await response.json();
      if (response.ok) {
        localStorage.setItem('auth_token', result.access_token);
        window.location.href = '/dashboard';
      } else {
        alert(result.error || 'Login failed');
      }
    } catch (error) {
      console.error('Password auth failed:', error);
    }
  };

  return (
    <div className="auth-container">
      <div className="auth-tabs">
        <button 
          onClick={() => setAuthMethod('bankid')}
          className={authMethod === 'bankid' ? 'active' : ''}
        >
          BankID
        </button>
        <button 
          onClick={() => setAuthMethod('password')}
          className={authMethod === 'password' ? 'active' : ''}
        >
          Email
        </button>
      </div>

      {authMethod === 'bankid' && (
        <div className="bankid-auth">
          <button onClick={handleBankIDAuth}>
            Authenticate with BankID
          </button>
        </div>
      )}

      {authMethod === 'password' && (
        <form onSubmit={handlePasswordAuth} className="password-auth">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <button type="submit">Sign In</button>
        </form>
      )}
    </div>
  );
}
```

## Custom User Registration Flow

### Scenario: Pre-register users before BankID verification

Allow users to create an account with email first, then verify with BankID later.

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  # ... other attributes

  actions do
    create :register do
      primary? true
      accept [:email, :given_name, :surname]
      argument :password, :string, allow_nil?: false, sensitive?: true
      argument :password_confirmation, :string, allow_nil?: false, sensitive?: true
      
      # Hash password and set initial verification status
      change set_attribute(:bankid_verified_at, nil)
      change AshAuthentication.Strategy.Password.HashPasswordChange
    end

    update :verify_with_bankid do
      accept [:personal_number, :given_name, :surname, :bankid_verified_at, :ip_address]
      
      # Ensure personal number is unique
      validate AshAuthentication.Strategy.Identity.IdentityValidation
      
      change fn changeset, _context ->
        # Verify that the provided personal number matches BankID data
        completion_data = Ash.Changeset.get_argument(changeset, :completion_data)
        if completion_data do
          changeset
          |> Ash.Changeset.change_attribute(:personal_number, completion_data.user.personal_number)
          |> Ash.Changeset.change_attribute(:given_name, completion_data.user.given_name)
          |> Ash.Changeset.change_attribute(:surname, completion_data.user.surname)
          |> Ash.Changeset.change_attribute(:bankid_verified_at, DateTime.utc_now())
        else
          changeset
        end
      end
    end
  end
end
```

### Custom Sign-in Action

```elixir
# lib/my_app/accounts/bank_id_actions.ex
defmodule MyApp.Accounts.BankIDActions do
  @moduledoc "Custom BankID actions for registration flow"

  def sign_in_with_registration_link(strategy, params, opts) do
    case AshAuthentication.BankID.Actions.sign_in(strategy, params, opts) do
      {:ok, user} ->
        # User already exists, normal sign-in
        {:ok, user}
        
      {:error, :user_not_found} ->
        # User doesn't exist, create registration link
        completion_data = params["completion_data"]
        
        {:ok, registration_token} = create_registration_token(completion_data, opts)
        
        {:error, :registration_required, %{
          message: "Please complete registration",
          registration_token: registration_token,
          user_info: completion_data.user
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_registration_token(completion_data, _opts) do
    # Create a short-lived token for registration completion
    Phoenix.Token.sign(
      MyAppWeb.Endpoint,
      "registration",
      %{
        completion_data: completion_data,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      },
      max_age: 3600
    )
  end
end
```

## Progressive Authentication

### Scenario: Basic auth first, then BankID verification

Require users to sign in with email/password first, then optionally verify with BankID for elevated privileges.

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  attributes do
    # ... other attributes
    
    attribute :verification_level, :atom, default: :basic
    attribute :last_verified_at, :utc_datetime_usec, allow_nil?: true
  end

  authentication do
    strategies do
      password do
        identity_field :email
        hashed_password_field :hashed_password
      end
      
      bank_id do
        order_resource MyApp.Accounts.BankIDOrder
        # Link to existing user by email lookup
        identity_field :email
        personal_number_field :personal_number
        given_name_field :given_name
        surname_field :surname
        verified_at_field :last_verified_at
      end
    end
  end

  actions do
    create :upgrade_verification do
      accept [:personal_number, :given_name, :surname, :last_verified_at, :ip_address]
      
      change fn changeset, _context ->
        # Only upgrade if user exists and has basic auth
        user = Ash.Changeset.data(changeset)
        if user.verification_level == :basic do
          changeset
          |> Ash.Changeset.change_attribute(:verification_level, :bankid_verified)
          |> Ash.Changeset.change_attribute(:last_verified_at, DateTime.utc_now())
        else
          changeset
        end
      end
    end
  end
end
```

## Role-Based Access with BankID

### Scenario: Different access levels based on verification method

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  attributes do
    # ... other attributes
    attribute :role, :atom, default: :user
    attribute :access_level, :atom, default: :basic
  end

  # Add policies for different access levels
  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if expr(access_level == :admin)
    end

    policy action(:admin_only_action) do
      authorize_if expr(access_level == :admin)
    end

    policy action(:bankid_required) do
      authorize_if expr(access_level in [:verified, :admin])
    end
  end
end

# Custom sign-in action that sets roles based on verification
defmodule MyApp.Accounts.CustomBankIDActions do
  def sign_in_with_roles(strategy, params, opts) do
    case AshAuthentication.BankID.Actions.sign_in(strategy, params, opts) do
      {:ok, user} ->
        # Determine role based on verification method
        role = determine_role(user, params)
        
        updated_user = 
          user
          |> Ash.Changeset.for_update(:update_role, %{role: role})
          |> Ash.update!(opts)
          
        {:ok, updated_user}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp determine_role(user, _params) do
    cond do
      user.bankid_verified_at ->
        if is_admin_user?(user) do
          :admin
        else
          :verified_user
        end
        
      user.email ->
        :user
        
      true ->
        :guest
    end
  end

  defp is_admin_user?(user) do
    # Check against admin list or other criteria
    user.personal_number in System.get_env("ADMIN_PERSONAL_NUMBERS", "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
```

## Custom Token Handling

### Scenario: Enhanced JWT tokens with BankID verification level

```elixir
# lib/my_app/accounts/token.ex
defmodule MyApp.Accounts.Token do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  token do
    api MyApp.Accounts
    
    # Custom token generation with verification info
    after_action fn _changeset, token, _context ->
      user = Ash.load!(token, [:user]).user
      
      extra_claims = %{
        "verification_level" => user.access_level,
        "bankid_verified" => not is_nil(user.bankid_verified_at),
        "last_verified_at" => user.last_verified_at,
        "role" => user.role
      }
      
      {:ok, Ash.Resource.put_metadata(token, :extra_claims, extra_claims)}
    end
  end
end

# lib/my_app_web/auth_plug.ex
defmodule MyAppWeb.AuthPlug do
  use Plug.Builder

  plug :fetch_current_user
  plug :require_bankid_for_sensitive_routes

  defp fetch_current_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- MyAppWeb.Token.verify(token),
         {:ok, user} <- Ash.get(MyApp.Accounts.User, claims["sub"]) do
      assign(conn, :current_user, user)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  defp require_bankid_for_sensitive_routes(conn, _opts) do
    user = conn.assigns[:current_user]
    
    if sensitive_route?(conn.path_info) and (is_nil(user) or user.access_level == :basic) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "BankID verification required"}))
      |> halt()
    else
      conn
    end
  end

  defp sensitive_route?(path_parts) do
    Enum.any?(["/admin", "/sensitive", "/premium"], fn prefix ->
      List.starts_with?(path_parts, String.split(prefix, "/"))
    end)
  end
end
```

## Audit Logging

### Scenario: Comprehensive audit trail for BankID authentications

```elixir
# lib/my_app/accounts/audit_log.ex
defmodule MyApp.Accounts.AuditLog do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false
    attribute :action, :string, allow_nil?: false
    attribute :strategy, :string, allow_nil?: false
    attribute :ip_address, :string, allow_nil?: true
    attribute :user_agent, :string, allow_nil?: true
    attribute :success, :boolean, default: true
    attribute :error_code, :string, allow_nil?: true
    attribute :metadata, :map, allow_nil?: true
    attribute :created_at, :utc_datetime_usec, allow_nil?: false
  end

  actions do
    defaults [:read, :create]
  end
end

# Custom actions with audit logging
defmodule MyApp.Accounts.AuditedBankIDActions do
  def sign_in_with_audit(strategy, params, opts) do
    start_time = DateTime.utc_now()
    
    case AshAuthentication.BankID.Actions.sign_in(strategy, params, opts) do
      {:ok, user} ->
        # Log successful authentication
        create_audit_log(user, :sign_in, :bankid, params, true, nil, start_time)
        {:ok, user}
        
      {:error, reason} ->
        # Log failed authentication
        user_id = extract_user_id_from_error(reason)
        create_audit_log(nil, :sign_in, :bankid, params, false, reason, start_time, user_id)
        {:error, reason}
    end
  end

  defp create_audit_log(user, action, strategy, params, success, error_code, start_time, user_id \\ nil) do
    audit_data = %{
      user_id: if(user, do: user.id, else: user_id),
      action: to_string(action),
      strategy: to_string(strategy),
      ip_address: get_in(params, ["device_info", "ip_address"]),
      user_agent: get_in(params, ["device_info", "user_agent"]),
      success: success,
      error_code: if(success, do: nil, else: to_string(error_code)),
      metadata: %{
        order_ref: get_in(params, ["order_ref"]),
        completion_data: get_in(params, ["completion_data"])
      },
      created_at: start_time
    }

    # Create audit log asynchronously
    Task.start(fn ->
      MyApp.Accounts.AuditLog
      |> Ash.Changeset.for_create(:create, audit_data)
      |> Ash.create!()
    end)
  end
end
```

## Custom Error Handling

### Scenario: User-friendly error messages with localization

```elixir
# lib/my_app_web/error_helpers.ex
defmodule MyAppWeb.ErrorHelpers do
  def translate_bankid_error(error_code) do
    case error_code do
      "userCancel" -> dgettext("auth", "You cancelled the authentication")
      "expiredTransaction" -> dgettext("auth", "Authentication timed out. Please try again.")
      "noClient" -> dgettext("auth", "Please install the BankID app on your device")
      "certificateErr" -> dgettext("auth", "There was a problem with the authentication certificate")
      "alreadyInProgress" -> dgettext("auth", "Authentication is already in progress")
      "orderNotFound" -> dgettext("auth", "Authentication session expired. Please start over.")
      _ -> dgettext("auth", "Authentication failed. Please try again.")
    end
  end

  def get_error_suggestion(error_code) do
    case error_code do
      "userCancel" -> :retry
      "expiredTransaction" -> :retry
      "noClient" -> :install_app
      "certificateErr" -> :contact_support
      "orderNotFound" -> :restart
      _ -> :retry
    end
  end
end

# Frontend error handling component
function BankIDErrorHandler({ error, onRetry }) {
  const { t } = useTranslation('auth');
  
  const errorKey = error?.error_code || 'unknown';
  const message = t(`bankid.errors.${errorKey}`, { defaultValue: t('bankid.errors.unknown') });
  const suggestion = error?.error_code ? getErrorSuggestion(error.error_code) : 'retry';

  return (
    <div className="error-container">
      <Alert severity="error">
        {message}
      </Alert>
      
      {suggestion === 'retry' && (
        <Button onClick={onRetry} variant="contained" color="primary">
          {t('bankid.actions.retry')}
        </Button>
      )}
      
      {suggestion === 'install_app' && (
        <Button 
          href="https://www.bankid.com/bankid-i-din-dator/webb"
          target="_blank"
          variant="contained"
          color="primary"
        >
          {t('bankid.actions.install_app')}
        </Button>
      )}
      
      {suggestion === 'contact_support' && (
        <Button 
          href="/support"
          variant="outlined"
        >
          {t('bankid.actions.contact_support')}
        </Button>
      )}
    </div>
  );
}
```

## Testing Scenarios

### Scenario: End-to-end BankID testing with mocks

```elixir
# test/support/bankid_test_helpers.ex
defmodule BankIDTestHelpers do
  @test_personal_number "199001011234"
  @test_user %{
    "personalNumber" => @test_personal_number,
    "name" => "Test Testsson",
    "givenName" => "Test",
    "surname" => "Testsson"
  }

  def simulate_successful_flow(order_ref \\ "test-order-ref") do
    # Mock successful auth response
    Mox.expect(BankID.ClientMock, :auth, fn _params, _opts ->
      {:ok, %{
        "orderRef" => order_ref,
        "autoStartToken" => "test-auto-start",
        "qrStartToken" => "test-qr-token",
        "qrStartSecret" => "test-secret"
      }}
    end)

    # Mock successful collect
    Mox.expect(BankID.ClientMock, :collect, ^order_ref, fn _opts ->
      {:ok, %{
        "status" => "complete",
        "completionData" => %{
          "user" => @test_user,
          "device" => %{"ipAddress" => "127.0.0.1"}
        }
      }}
    end)
  end

  def simulate_cancelled_flow(order_ref \\ "test-order-ref") do
    Mox.expect(BankID.ClientMock, :auth, fn _params, _opts ->
      {:ok, %{
        "orderRef" => order_ref,
        "autoStartToken" => "test-auto-start"
      }}
    end)

    Mox.expect(BankID.ClientMock, :collect, ^order_ref, fn _opts ->
      {:ok, %{
        "status" => "failed",
        "hintCode" => "userCancel"
      }}
    end)
  end
end

# Integration test example
defmodule MyAppWeb.BankIDAuthIntegrationTest do
  use MyAppWeb.ConnCase
  import BankIDTestHelpers

  test "complete BankID authentication flow", %{conn: conn} do
    simulate_successful_flow()

    # Start authentication
    conn = post(conn, "/auth/user/bank_id/initiate", %{
      "return_url" => "/dashboard"
    })

    assert json_response(conn, 200)["status"] == "pending"
    order_ref = json_response(conn, 200)["order_ref"]

    # Poll until complete
    conn = get(conn, "/auth/user/bank_id/poll?order_ref=#{order_ref}")
    poll_response = json_response(conn, 200)
    assert poll_response["status"] == "complete"

    # Complete sign-in
    conn = post(conn, "/auth/user/bank_id", %{
      "order_ref" => order_ref,
      "completion_data" => poll_response["completion_data"]
    })

    response = json_response(conn, 200)
    assert response["access_token"]
    assert response["user"]["personal_number"] == "199001011234"
  end
end
```

## Performance Optimization

### Scenario: Optimizing BankID performance with caching and connection pooling

```elixir
# lib/my_app/bankid_optimizer.ex
defmodule MyApp.BankIDOptimizer do
  use GenServer
  require Logger

  # Cache for recent auth results
  @cache_name :bankid_auth_cache
  @cache_ttl :timer.hours(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@cache_name, [:set, :public, :named_table])
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cache_ttl)
    
    {:ok, %{}}
  end

  def cached_auth(params, opts \\ []) do
    cache_key = generate_cache_key(params)
    
    case :ets.lookup(@cache_name, cache_key) do
      [{^cache_key, result, timestamp}] ->
        if recent?(timestamp) do
          Logger.debug("BankID cache hit for #{cache_key}")
          {:ok, result}
        else
          :ets.delete(@cache_name, cache_key)
          perform_auth_and_cache(params, opts, cache_key)
        end
        
      [] ->
        Logger.debug("BankID cache miss for #{cache_key}")
        perform_auth_and_cache(params, opts, cache_key)
    end
  end

  defp perform_auth_and_cache(params, opts, cache_key) do
    case BankID.Client.auth(params, opts) do
      {:ok, result} ->
        :ets.insert(@cache_name, {cache_key, result, DateTime.utc_now()})
        {:ok, result}
        
      {:error, reason} ->
        # Don't cache errors except for specific cases
        if cacheable_error?(reason) do
          :ets.insert(@cache_name, {cache_key, reason, DateTime.utc_now()})
        end
        {:error, reason}
    end
  end

  defp generate_cache_key(params) do
    # Create cache key from non-sensitive params
    params
    |> Map.take(["endUserIp", "userVisibleData"])
    |> Jason.encode!()
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp recent?(timestamp) do
    DateTime.diff(DateTime.utc_now(), timestamp, :millisecond) < @cache_ttl
  end

  defp cacheable_error?(reason) when reason in [:alreadyInProgress, :maintenance] do
    true
  end
  defp cacheable_error?(_), do: false

  def handle_info(:cleanup, state) do
    # Remove expired cache entries
    now = DateTime.utc_now()
    
    :ets.tab2list(@cache_name)
    |> Enum.each(fn {key, _value, timestamp} ->
      if not recent?(timestamp) do
        :ets.delete(@cache_name, key)
      end
    end)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cache_ttl)
    
    {:noreply, state}
  end
end

# Enhanced BankID configuration with optimization
# config/config.exs
config :my_app, MyApp.BankIDOptimizer,
  enabled: true,
  cache_ttl: :timer.hours(1),
  cleanup_interval: :timer.hours(2)

config :bankid, :client,
  http_opts: [
    timeout: 10_000,
    recv_timeout: 10_000,
    hackney: [
      pool: :bankid_pool,
      pool_size: 10,
      timeout: 10_000
    ]
  ]
```