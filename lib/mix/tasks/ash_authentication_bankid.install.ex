if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.AshAuthenticationBankid.Install do
    @moduledoc """
    Installs BankID authentication into a Phoenix application using Ash Authentication.

    ## Usage

        mix ash_authentication_bankid.install

    ## Options

      * `--user`, `-u` - The user resource module (default: auto-detected from AshAuthentication)
      * `--domain`, `-d` - The Ash domain module (default: auto-detected from user resource)
      * `--web-module`, `-w` - The Phoenix web module (default: YourAppWeb)

    ## What this installer does

    1. Adds BankID attributes to your User resource (personal_number, given_name, surname, etc.)
    2. Configures the BankID authentication strategy
    3. Creates a BankIDOrder resource for tracking authentication sessions
    4. Creates a BankIDLive LiveView for the authentication UI
    5. Creates an AuthCallbackController for session management
    6. Adds necessary routes to your router
    7. Ensures the email field allows nil (BankID doesn't provide emails)
    8. Generates database migrations

    ## After installation

    Run the following commands:

        mix deps.get
        mix ash.codegen
        mix ecto.migrate

    Then start your server and visit:

        http://localhost:4000/auth/user/bank_id
    """

    use Igniter.Mix.Task

    @shortdoc "Installs BankID authentication strategy"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash,
        adds_deps: [
          {:bankid, "~> 0.1.0"},
          {:ash_authentication_bankid, "~> 0.1.0"}
        ],
        installs: [],
        extra_args?: false,
        positional: [],
        schema: [
          user: :string,
          domain: :string,
          web_module: :string
        ],
        aliases: [
          u: :user,
          d: :domain,
          w: :web_module
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options =
        igniter.args.options
        |> Keyword.put_new_lazy(:domain, fn ->
          Igniter.Project.Module.module_name(igniter, "Accounts")
        end)
        |> Keyword.put_new_lazy(:web_module, fn ->
          app_name = Igniter.Project.Application.app_name(igniter)
          web_module_name = "#{app_name |> to_string() |> Macro.camelize()}Web"
          Igniter.Project.Module.parse(web_module_name)
        end)

      options =
        options
        |> Keyword.put_new_lazy(:user, fn ->
          Module.concat(options[:domain], User)
        end)
        |> Keyword.update!(:domain, &maybe_parse_module/1)
        |> Keyword.update!(:user, &maybe_parse_module/1)
        |> Keyword.update!(:web_module, &maybe_parse_module/1)

      order_resource = Module.concat(options[:domain], BankIDOrder)

      case Igniter.Project.Module.module_exists(igniter, options[:user]) do
        {true, igniter} ->
          igniter
          |> add_bankid_to_user(options, order_resource)
          |> create_bankid_order_resource(options, order_resource)
          |> add_expunger_to_supervision_tree(options, order_resource)
          |> create_bankid_live(options)
          |> create_auth_callback_controller(options)
          |> create_qr_code_hook(options)
          |> add_routes(options)
          |> Ash.Igniter.codegen("add_bankid_auth")
          |> Igniter.add_notice("""

          BankID authentication has been installed!

          Next steps:

          1. Install dependencies:
             mix deps.get

          2. Generate migrations:
             mix ash.codegen

          3. Run migrations:
             mix ecto.migrate

          4. Start your server and visit:
             http://localhost:4000/auth/user/bank_id

          5. Test with BankID test personal numbers:
             - 198803290003
             - 199006292360

          User resource: #{inspect(options[:user])}
          Order resource: #{inspect(order_resource)}
          """)

        {false, igniter} ->
          Igniter.add_issue(igniter, """
          User module #{inspect(options[:user])} was not found.

          Perhaps you have not yet installed ash_authentication?

          Run: mix ash_authentication.install
          """)
      end
    end

    defp maybe_parse_module(module) when is_binary(module), do: Igniter.Project.Module.parse(module)
    defp maybe_parse_module(module), do: module
  end
end
