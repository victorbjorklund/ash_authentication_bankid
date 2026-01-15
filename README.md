# Ash Authentication BankID

Swedish BankID authentication strategy for Ash Authentication.

## Disclaimer

This is a very early version of the library, so things are probably going to change in the future.

## Features

- ✅ QR code-based cross-device authentication
- ✅ Same-device mobile authentication
- ✅ Automatic user creation with upsert
- ✅ Session binding for security
- ✅ JWT token generation
- ✅ Order expiration and cleanup

## Installation

### Using the Igniter Mix Task (Recommended)

The easiest way to install BankID authentication is using the Igniter-based installer:

```bash
mix ash_authentication_bankid.install
```

#### Options

- `--user`, `-u` - The user resource module (default: auto-detected from AshAuthentication)
- `--domain`, `-d` - The Ash domain module (default: auto-detected from user resource)
- `--web-module`, `-w` - The Phoenix web module (default: YourAppWeb)

#### What the Installer Does

1. Adds BankID attributes to your User resource (personal_number, given_name, surname, etc.)
2. Configures the BankID authentication strategy
3. Creates a BankIDOrder resource for tracking authentication sessions
4. Creates a BankIDLive LiveView for the authentication UI
5. Creates an AuthCallbackController for session management
6. Adds necessary routes to your router
7. Ensures the email field allows nil (BankID doesn't provide emails)
8. Generates database migrations
9. Creates a JavaScript hook for the countdown timer
10. Adds an expunger to your supervision tree for cleanup

#### After Installation

Run the following commands to complete the setup:

```bash
mix deps.get
mix ash.codegen
mix ecto.migrate
```

#### Manual Step Required

After running the installer, you need to manually register the JavaScript hook. Update your `assets/js/app.js`:

```javascript
// Add this import near the top
import { CountdownTimer } from "./bankid_hooks"

// Add this to your Hooks object before creating LiveSocket
Hooks.CountdownTimer = CountdownTimer
```

Without this step, the countdown timer will not work!

#### Testing the Installation

Start your server and visit:

```
http://localhost:4000/auth/user/bank_id
```

You can test with BankID's test personal numbers:
- `198803290003`
- `199006292360`

### Manual Installation

If you prefer to install manually, add to your `mix.exs`:

```elixir
def deps do
  [
    {:ash_authentication_bankid, "~> 0.1.0"}
  ]
end
```

Then follow the manual setup documentation (TODO: link to docs).

## Configuration

See documentation for full setup instructions.

## License

MIT
