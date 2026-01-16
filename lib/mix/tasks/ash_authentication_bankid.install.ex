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

  defp add_bankid_to_user(igniter, options, order_resource) do
    igniter
    # Add AshAuthentication.BankID to extensions list
    |> Igniter.Project.Module.find_and_update_module!(options[:user], fn zipper ->
      add_extension_to_use(zipper, AshAuthentication.BankID)
    end)
    # Ensure email allows nil (BankID doesn't provide emails)
    |> ensure_email_allows_nil(options[:user])
    # Add BankID attributes
    |> Ash.Resource.Igniter.add_new_attribute(options[:user], :personal_number, """
    attribute :personal_number, :string do
      allow_nil? true
      public? true
    end
    """)
    |> Ash.Resource.Igniter.add_new_attribute(options[:user], :given_name, """
    attribute :given_name, :string do
      allow_nil? true
      public? true
    end
    """)
    |> Ash.Resource.Igniter.add_new_attribute(options[:user], :surname, """
    attribute :surname, :string do
      allow_nil? true
      public? true
    end
    """)
    |> Ash.Resource.Igniter.add_new_attribute(options[:user], :bankid_verified_at, """
    attribute :bankid_verified_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end
    """)
    |> Ash.Resource.Igniter.add_new_attribute(options[:user], :ip_address, """
    attribute :ip_address, :string do
      allow_nil? true
      public? true
    end
    """)
    # Add identity for personal_number
    |> Ash.Resource.Igniter.add_new_identity(options[:user], :unique_personal_number, """
    identity :unique_personal_number, [:personal_number]
    """)
    # Add BankID strategy
    |> AshAuthentication.Igniter.add_new_strategy(options[:user], :bank_id, :bank_id, """
    bank_id do
      order_resource #{inspect(order_resource)}
      identity_field :personal_number
      personal_number_field :personal_number
      given_name_field :given_name
      surname_field :surname
      verified_at_field :bankid_verified_at
      ip_address_field :ip_address
    end
    """)
  end

  defp ensure_email_allows_nil(igniter, user_resource) do
    Igniter.Project.Module.find_and_update_module!(igniter, user_resource, fn zipper ->
      with {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :attributes,
               1
             ),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :attribute,
               [1, 2, 3],
               &Igniter.Code.Function.argument_equals?(&1, 0, :email)
             ),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :allow_nil?,
               1,
               &Igniter.Code.Function.argument_equals?(&1, 0, false)
             ) do
        {:ok, Sourceror.Zipper.replace(zipper, quote(do: allow_nil?(true)))}
      else
        _ ->
          {:ok, zipper}
      end
    end)
  end

  defp create_bankid_order_resource(igniter, options, order_resource) do
    repo = find_repo(igniter)

    # Generate the BankIDOrder resource using compose_task
    # Note: Do NOT use --default-actions since OrderResource extension adds all CRUD actions
    # Use --extend postgres to get proper data_layer setup
    Igniter.compose_task(igniter, "ash.gen.resource", [
      inspect(order_resource),
      "--domain",
      inspect(options[:domain]),
      "--extend",
      "AshAuthentication.BankID.OrderResource,postgres"
    ])
    |> then(fn igniter ->
      # Update the postgres table name and repo
      Igniter.Project.Module.find_and_update_module!(igniter, order_resource, fn zipper ->
        # Navigate to postgres block and update table name
        with {:ok, zipper} <-
               Igniter.Code.Function.move_to_function_call_in_current_scope(
                 zipper,
                 :postgres,
                 1
               ),
             {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper) do
          # Update the table setting
          zipper =
            case Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :table, 1) do
              {:ok, table_zipper} ->
                Sourceror.Zipper.replace(
                  table_zipper,
                  Sourceror.parse_string!(~s|table "bankid_orders"|)
                )

              _ ->
                # Add table if not present
                Igniter.Code.Common.add_code(zipper, ~s|table "bankid_orders"|)
            end

          # Update the repo setting - need to move back to do block first
          zipper =
            case Sourceror.Zipper.up(zipper) do
              nil ->
                zipper

              parent_zipper ->
                case Igniter.Code.Common.move_to_do_block(parent_zipper) do
                  {:ok, do_zipper} ->
                    case Igniter.Code.Function.move_to_function_call_in_current_scope(
                           do_zipper,
                           :repo,
                           1
                         ) do
                      {:ok, repo_zipper} ->
                        Sourceror.Zipper.replace(
                          repo_zipper,
                          Sourceror.parse_string!("repo #{inspect(repo)}")
                        )

                      _ ->
                        Igniter.Code.Common.add_code(do_zipper, "repo #{inspect(repo)}")
                    end

                  _ ->
                    zipper
                end
            end

          {:ok, zipper}
        else
          _ -> {:ok, zipper}
        end
      end)
    end)
  end

  defp add_expunger_to_supervision_tree(igniter, _options, order_resource) do
    igniter
    |> Igniter.Project.Application.add_new_child(
      {AshAuthentication.BankID.Expunger,
       [
         order_resource: order_resource,
         order_ttl: 300,
         cleanup_interval: 300_000,
         consumed_order_ttl: 86_400
       ]}
    )
  end

  defp create_bankid_live(igniter, options) do
    live_module = Module.concat(options[:web_module], BankIDLive)
    user_module = options[:user]
    domain = options[:domain]
    order_resource = Module.concat(domain, BankIDOrder)

    live_code = """
    @moduledoc \"\"\"
    LiveView for BankID authentication.

    ## Security

    This LiveView implements several security measures to protect sensitive data:

    1. **Sensitive Data Protection**: Both `qr_start_secret` and `session_id` are NEVER
       stored in socket assigns. They're kept in `socket.private` to prevent accidental
       exposure through debugging code like `{inspect(@order)}`.

    2. **Order Sanitization**: Before assigning orders to the socket, we strip out
       sensitive fields (qr_start_secret, session_id) using `sanitize_order/1`.

    3. **Session Binding**: Orders are bound to Phoenix sessions server-side to prevent
       order hijacking attacks. The session_id is stored in `socket.private` and used
       for validation when renewing orders.

    4. **One-Time Use**: Orders are marked as consumed after successful authentication
       to prevent replay attacks.
    \"\"\"
    use #{inspect(options[:web_module])}, :live_view

    require Logger
    require Ash.Query

    import AshAuthentication.BankID.Helpers

    alias AshAuthentication.BankID.UserMessages
    alias BankID.Client
    alias BankID.QRCode

    @max_renewals 10
    @order_ttl 300
    @qr_code_width 200

    # Status constants
    @status_pending "pending"
    @status_complete "complete"
    @status_failed "failed"
    @status_loading "loading"
    @status_error "error"

    @impl true
    def mount(_params, session, socket) do
        if connected?(socket) do
          # Get locale from session or default to English
          locale =
            case Map.get(session, "locale", "en") do
              "sv" -> :sv
              _ -> :en
            end

          # TODO: Replace with actual user IP from connection
          socket =
            socket
            |> assign(:user_ip, "127.0.0.1")
            |> assign(:locale, locale)

          case initiate_bank_id(socket) do
            {:ok, order} ->
              schedule_all_timers()

              {:ok,
               socket
               |> assign_order_state(order)
               |> assign(:renewal_count, 0)
               |> assign(:auth_start_time, System.system_time(:second))
               |> assign(:order_ttl, @order_ttl)}

            {:error, reason} ->
              {:ok,
               assign_initial_state(socket,
                 error: "Failed to initiate BankID: \#{inspect(reason)}"
               )}
          end
        else
          {:ok, assign_initial_state(socket)}
        end
      end

      @impl true
      def handle_info(:renew_order, socket) do
        # Skip renewal if not pending, or if user has started interacting with BankID
        # When hint_code is "started" or "userSign", the user is actively working with
        # the current order and we must NOT create a new one
        order = socket.assigns.order
        hint_code = order && order.hint_code

        if current_status(socket) != @status_pending or user_is_active?(hint_code) do
          {:noreply, socket}
        else
          elapsed = System.system_time(:second) - socket.assigns.auth_start_time

          # Check if we should continue renewing
          if elapsed < @order_ttl and socket.assigns.renewal_count < @max_renewals do
            case renew_bank_id_order(socket) do
              {:ok, new_order} ->
                schedule_renewal()

                # Sanitize new order (removes sensitive fields)
                safe_order = sanitize_order(new_order)

                {:noreply,
                 socket
                 |> assign(:order, safe_order)
                 |> assign(:qr_svg, generate_qr_svg(safe_order, new_order.qr_start_secret))
                 |> assign(:renewal_count, socket.assigns.renewal_count + 1)
                 # Store new sensitive data in private socket state
                 |> put_private(:qr_secret, new_order.qr_start_secret)
                 |> put_private(:session_id, new_order.session_id)}

              {:error, reason} ->
                Logger.error("Order renewal failed: \#{inspect(reason)}")
                # Continue with existing order, don't fail
                {:noreply, socket}
            end
          else
            # Max renewals reached or time expired
            Logger.info("Max renewals reached or authentication window expired")

            timeout_minutes = div(@order_ttl, 60)
            timeout_message = UserMessages.timeout_message(timeout_minutes, socket.assigns.locale)

            {:noreply,
             socket
             |> assign(:order, nil)
             |> assign(:error, timeout_message)}
          end
        end
      end

      @impl true
      def handle_info(:poll_status, socket) do
        # Don't poll if there's already an error or no order
        if socket.assigns.error || is_nil(socket.assigns.order) do
          {:noreply, socket}
        else
          case poll_bank_id(socket) do
            {:ok, updated_order} ->
              socket = assign(socket, :order, updated_order)
              status = updated_order.status

              case status do
                @status_complete ->
                  case complete_bank_id(socket, updated_order.order_ref) do
                    {:ok, user} ->
                      token = Ash.Resource.get_metadata(user, :token)
                      {:noreply, redirect(socket, to: "/auth/callback?token=\#{token}")}

                    {:error, reason} ->
                      Logger.error("Failed to complete BankID authentication: \#{inspect(reason)}")
                      {:noreply, assign(socket, :error, "Authentication failed")}
                  end

                @status_failed ->
                  {:noreply, assign(socket, :error, "BankID authentication failed")}

                @status_pending ->
                  schedule_poll()
                  {:noreply, socket}

                _ ->
                  schedule_poll()
                  {:noreply, socket}
              end

            {:error, reason} ->
              Logger.error("Failed to poll BankID status: \#{inspect(reason)}")
              schedule_poll()
              {:noreply, socket}
          end
        end
      end

      @impl true
      def handle_info(:update_qr_content, socket) do
        # Only update if we're still pending and have the necessary data
        # Stop updating QR if user has started interacting (they've already scanned)
        if should_update_qr?(socket) do
          # Retrieve secret from private socket state (never exposed to client)
          qr_svg = generate_qr_svg(socket.assigns.order, socket.private.qr_secret)

          schedule_qr_update()
          {:noreply, assign(socket, :qr_svg, qr_svg)}
        else
          {:noreply, socket}
        end
      end

      @impl true
      def handle_event("retry", _params, socket) do
        case initiate_bank_id(socket) do
          {:ok, order} ->
            schedule_all_timers()

            {:noreply,
             socket
             |> assign_order_state(order)
             |> assign(:renewal_count, 0)
             |> assign(:auth_start_time, System.system_time(:second))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:order, nil)
             |> assign(:error, "Failed to initiate BankID: \#{inspect(reason)}")}
        end
      end

      @impl true
      def handle_event("cancel", _params, socket) do
        {:noreply, redirect(socket, to: "/")}
      end

      # Status derivation helper
      defp current_status(%{assigns: assigns}), do: current_status(assigns)
      defp current_status(%{error: error}) when not is_nil(error), do: @status_error
      defp current_status(%{order: nil}), do: @status_loading
      defp current_status(%{order: order}), do: order.status

      # Timer scheduling helper
      defp schedule_all_timers do
        schedule_poll()
        schedule_renewal()
        schedule_qr_update()
      end

      # QR code generation helper
      defp generate_qr_svg(order, qr_secret) do
        QRCode.generate_svg(
          order.qr_start_token,
          order.start_t,
          qr_secret,
          width: @qr_code_width
        )
      end

      # Sanitize order to remove sensitive fields before assigning to socket
      defp sanitize_order(order) do
        %{
          id: order.id,
          order_ref: order.order_ref,
          qr_start_token: order.qr_start_token,
          auto_start_token: order.auto_start_token,
          start_t: order.start_t,
          status: order.status,
          hint_code: order.hint_code,
          completion_data: order.completion_data,
          ip_address: order.ip_address,
          inserted_at: order.inserted_at,
          updated_at: order.updated_at
          # Explicitly excluded: qr_start_secret, session_id
        }
      end

      # Socket assignment helpers
      defp assign_order_state(socket, order) do
        # Sanitize order before assigning to socket (removes sensitive fields)
        safe_order = sanitize_order(order)

        # Generate QR with secret
        qr_svg = generate_qr_svg(safe_order, order.qr_start_secret)

        socket
        |> assign(:order, safe_order)
        |> assign(:qr_svg, qr_svg)
        |> assign(:error, nil)
        # Store sensitive data in private socket state (never sent to client)
        |> put_private(:qr_secret, order.qr_start_secret)
        |> put_private(:session_id, order.session_id)
      end

      defp assign_initial_state(socket, opts \\\\ []) do
        error = Keyword.get(opts, :error)

        socket
        |> assign(:order, nil)
        |> assign(:qr_svg, nil)
        |> assign(:error, error)
        |> assign(:renewal_count, 0)
        |> assign(:auth_start_time, System.system_time(:second))
        |> assign(:order_ttl, @order_ttl)
        |> assign(:user_ip, "127.0.0.1")
        |> assign(:locale, :en)
      end

      defp user_is_active?(hint_code) do
        hint_code in ["started", "userSign"]
      end

      defp order_data_changed?(collect_result, order) do
        collect_result.status != order.status or
          collect_result[:hint_code] != order.hint_code or
          collect_result[:completion_data] != order.completion_data
      end

      defp should_update_qr?(socket) do
        order = socket.assigns.order

        current_status(socket) == @status_pending &&
          order && order.qr_start_token &&
          !user_is_active?(order.hint_code)
      end

      # Helper to build order parameters from auth data
      defp build_order_params(auth_data, session_id, user_ip) do
        %{
          order_ref: auth_data.order_ref,
          qr_start_token: auth_data.qr_start_token,
          qr_start_secret: auth_data.qr_start_secret,
          auto_start_token: auth_data.auto_start_token,
          start_t: auth_data.start_t,
          session_id: session_id,
          ip_address: user_ip,
          status: @status_pending
        }
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="min-h-screen bg-gray-50 flex items-center justify-center px-4">
          <div class="w-full max-w-md">
            <%= if current_status(assigns) == "loading" do %>
              <div class="bg-white rounded-lg shadow-sm p-12 text-center">
                <p class="text-gray-600">{UserMessages.ui_text(:loading, @locale)}</p>
              </div>
            <% end %>

            <%= if current_status(assigns) == "pending" do %>
              <div class="bg-white rounded-lg shadow-sm p-8">
                <!-- Back button -->
                <button
                  onclick="window.history.back()"
                  class="flex items-center justify-center w-10 h-10 rounded-full bg-gray-800 text-white hover:bg-gray-700 transition-colors mb-6"
                  aria-label="Go back"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
                  </svg>
                </button>

                <!-- Title -->
                <h1 class="text-2xl font-semibold text-gray-800 text-center mb-6">
                  {UserMessages.ui_text(:title, @locale)}
                </h1>

                <!-- Instructions -->
                <p class="text-center text-gray-700 mb-2">
                  {UserMessages.ui_text(:instruction_1, @locale)}
                </p>
                <p class="text-center text-gray-700 mb-8">
                  {UserMessages.ui_text(:instruction_2, @locale)}
                </p>

                <!-- QR Code -->
                <div class="flex justify-center mb-6">
                  <%= if @order && @order.auto_start_token do %>
                    <a
                      href={"bankid:///?autostarttoken=\#{@order.auto_start_token}&redirect=null"}
                      role="button"
                      aria-label={UserMessages.ui_text(:qr_aria_label_clickable, @locale)}
                      class="cursor-pointer focus:outline-none focus:ring-2 focus:ring-gray-800 focus:ring-offset-2 rounded"
                    >
                      <%= Phoenix.HTML.raw(@qr_svg) %>
                    </a>
                  <% else %>
                    <div role="img" aria-label={UserMessages.ui_text(:qr_aria_label, @locale)}>
                      <%= Phoenix.HTML.raw(@qr_svg) %>
                    </div>
                  <% end %>
                </div>

                <!-- Countdown Bar and Text (phx-update="ignore" prevents LiveView from interfering with timer) -->
                <div phx-update="ignore" id="countdown-wrapper">
                  <div class="mb-2">
                    <div class="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
                      <div
                        id="countdown-bar"
                        class="bg-gray-800 h-2"
                        style="width: 100%"
                        phx-hook="CountdownTimer"
                        data-start-time={@auth_start_time}
                        data-ttl={@order_ttl}
                      ></div>
                    </div>
                  </div>

                  <!-- Countdown Text -->
                   <p id="countdown-text" class="text-center text-sm text-gray-600 mb-8">
                     <%= if @order_ttl >= 60 do %>
                       {UserMessages.ui_text(:time_left_minutes, @locale).(ceil(@order_ttl / 60))}
                     <% else %>
                       {UserMessages.ui_text(:time_left_less_than_minute, @locale)}
                     <% end %>
                   </p>
                </div>

                <!-- Open on this device button -->
                <%= if @order && @order.auto_start_token do %>
                  <a
                    href={"bankid:///?autostarttoken=\#{@order.auto_start_token}&redirect=null"}
                    class="block w-full text-center py-3 px-4 border-2 border-gray-800 text-gray-800 rounded-lg font-medium hover:bg-gray-50 transition-colors"
                  >
                    {UserMessages.ui_text(:open_on_device, @locale)}
                  </a>
                <% end %>
              </div>
            <% end %>

            <%= if current_status(assigns) == "complete" do %>
              <div class="bg-white rounded-lg shadow-sm p-12 text-center">
                <div class="text-green-600 text-6xl mb-4">✓</div>
                <p class="text-xl font-semibold text-gray-800">{UserMessages.ui_text(:success_title, @locale)}</p>
                <p class="text-sm text-gray-600 mt-2">{UserMessages.ui_text(:success_subtitle, @locale)}</p>
              </div>
            <% end %>

            <%= if @error do %>
              <div class="bg-red-50 rounded-lg shadow-sm p-12 text-center">
                <!-- Error Icon -->
                <div class="flex justify-center mb-6">
                  <div class="w-20 h-20 rounded-full bg-red-300 flex items-center justify-center">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-10 w-10 text-gray-800" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
                    </svg>
                  </div>
                </div>

                <!-- Error Title -->
                <h2 class="text-2xl font-semibold text-gray-800 mb-4">
                  {UserMessages.ui_text(:error_title, @locale)}
                </h2>

                <!-- Error Description -->
                <p class="text-gray-700 mb-8">
                  <%= @error %>
                </p>

                <!-- Action Buttons -->
                <div class="flex gap-4 justify-center">
                  <button
                    phx-click="cancel"
                    class="px-6 py-3 text-gray-800 font-medium hover:bg-red-100 transition-colors rounded-lg"
                  >
                    {UserMessages.ui_text(:cancel, @locale)}
                  </button>
                  <button
                    phx-click="retry"
                    class="px-6 py-3 bg-gray-800 text-white font-medium hover:bg-gray-700 transition-colors rounded-lg"
                  >
                    {UserMessages.ui_text(:try_again, @locale)}
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        \"\"\"
      end

      defp initiate_bank_id(socket) do
        user_ip = socket.assigns.user_ip

        case Client.authenticate(user_ip) do
          {:ok, auth_data} ->
            session_id = generate_session_id()
            order_params = build_order_params(auth_data, session_id, user_ip)

            case #{inspect(order_resource)}
                 |> Ash.Changeset.for_create(:create, order_params)
                 |> Ash.create() do
              {:ok, order} ->
                {:ok, order}

              {:error, reason} ->
                Logger.error("Failed to create BankID order: \#{inspect(reason)}")
                {:error, "Failed to create order"}
            end

          {:error, reason} ->
            Logger.error("Failed to initiate BankID authentication: \#{inspect(reason)}")
            {:error, "Failed to initiate BankID"}
        end
      end

      defp renew_bank_id_order(socket) do
        old_order = socket.assigns.order
        # Retrieve session_id from private socket state (not in sanitized order)
        session_id = socket.private.session_id
        user_ip = socket.assigns.user_ip

        # Verify old order exists in database (security check)
        with {:ok, verified_order} when not is_nil(verified_order) <-
               #{inspect(order_resource)}
               |> Ash.Query.filter(order_ref == ^old_order.order_ref and session_id == ^session_id)
               |> Ash.read_one(),
             # Create new order
             {:ok, auth_data} <- Client.authenticate(user_ip),
             order_params <- build_order_params(auth_data, session_id, user_ip),
             {:ok, new_order} <-
               #{inspect(order_resource)}
               |> Ash.Changeset.for_create(:create, order_params)
               |> Ash.create() do
          # Old orders will be cleaned up by a separate cleanup process
          Logger.debug("Created new BankID order \#{auth_data.order_ref}, old order \#{verified_order.order_ref} will be cleaned up later")

          {:ok, new_order}
        else
          {:ok, nil} ->
            {:error, "Old order not found"}

          {:error, reason} ->
            Logger.error("Failed to renew order: \#{inspect(reason)}")
            {:error, reason}
        end
      end

      defp poll_bank_id(socket) do
        order = socket.assigns.order

        if is_nil(order) do
          {:error, "No order in assigns"}
        else
          case Client.collect(order.order_ref) do
            {:ok, collect_result} ->
              # Only update database if something changed
              if order_data_changed?(collect_result, order) do
                #{inspect(order_resource)}
                |> Ash.Query.filter(id == ^order.id)
                |> Ash.bulk_update(:update, %{
                  status: collect_result.status,
                  hint_code: collect_result[:hint_code],
                  completion_data: collect_result[:completion_data]
                })
                |> case do
                  %Ash.BulkResult{status: :success} -> :ok
                  %Ash.BulkResult{errors: errors} ->
                    Logger.warning("Failed to update order: \#{inspect(errors)}")
                  {:error, reason} ->
                    Logger.warning("Failed to update order: \#{inspect(reason)}")
                end
              end

              # Return updated order data for caching in assigns (even if unchanged)
              updated_order = %{
                order
                | status: collect_result.status,
                  hint_code: collect_result[:hint_code],
                  completion_data: collect_result[:completion_data]
              }

              {:ok, updated_order}

            {:error, reason} ->
              Logger.error("Failed to collect BankID status: \#{inspect(reason)}")
              {:error, "Failed to poll order"}
          end
        end
      end

      defp complete_bank_id(socket, order_ref) do
        # Get session_id from socket.private for security validation
        session_id = socket.private[:session_id]

        case #{inspect(user_module)}
             |> Ash.Changeset.for_create(:sign_in_with_bank_id, %{order_ref: order_ref, session_id: session_id})
             |> Ash.Changeset.set_context(%{private: %{ash_authentication?: true}})
             |> Ash.create() do
          {:ok, user} ->
            {:ok, user}

          {:error, reason} ->
            Logger.error("Failed to complete BankID authentication: \#{inspect(reason)}")
            {:error, "Authentication failed"}
        end
      end
    """

    Igniter.Project.Module.create_module(igniter, live_module, live_code)
  end

  defp create_auth_callback_controller(igniter, options) do
    controller_module = Module.concat(options[:web_module], AuthCallbackController)

    controller_code = """
    @moduledoc \"\"\"
    Controller to handle authentication callbacks and set session.
    \"\"\"
    use #{inspect(options[:web_module])}, :controller

    def callback(conn, %{"token" => token}) do
      conn
      |> put_session(:user_token, token)
      |> put_flash(:info, "Successfully authenticated with BankID!")
      |> redirect(to: "/")
    end

    def callback(conn, _params) do
      conn
      |> put_flash(:error, "Authentication token missing")
      |> redirect(to: "/")
    end
    """

    Igniter.Project.Module.create_module(igniter, controller_module, controller_code)
  end

  defp create_qr_code_hook(igniter, _options) do
    hook_path = "assets/js/bankid_hooks.js"

    hook_code = """
    /**
     * Phoenix LiveView hook for authentication countdown timer
     *
     * Uses pure client-side timing to avoid sync issues with server updates.
     * Counts down from TTL based on when the timer was first mounted.
     */
    export const CountdownTimer = {
      mounted() {
        // Store the client-side timestamp when authentication started
        this.clientStartTime = Math.floor(Date.now() / 1000);
        this.ttl = parseInt(this.el.dataset.ttl);

        // Update immediately
        this.updateCountdown();

        // Update every second
        this.interval = setInterval(() => this.updateCountdown(), 1000);
      },

      updateCountdown() {
        const now = Math.floor(Date.now() / 1000);
        const elapsed = now - this.clientStartTime;
        const remaining = Math.max(0, this.ttl - elapsed);

        // Update progress bar width
        const percentage = (remaining / this.ttl) * 100;
        this.el.style.width = `${percentage}%`;

        // Update countdown text (minutes only)
        const countdownText = document.getElementById('countdown-text');
        if (countdownText) {
          if (remaining <= 0) {
            countdownText.textContent = 'Time expired';
          } else {
            const minutes = Math.ceil(remaining / 60);

            if (minutes > 0) {
              countdownText.textContent = `${minutes} minute${minutes !== 1 ? 's' : ''} left`;
            } else {
              countdownText.textContent = 'Less than a minute left';
            }
          }
        }

        // Stop updating if time is up
        if (remaining <= 0 && this.interval) {
          clearInterval(this.interval);
          this.interval = null;
        }
      },

      destroyed() {
        if (this.interval) {
          clearInterval(this.interval);
          this.interval = null;
        }
      }
    };
    """

    igniter
    |> Igniter.create_new_file(hook_path, hook_code)
    |> Igniter.add_notice("""

    ⚠️  IMPORTANT: Manual steps required!

    JavaScript hook created at #{hook_path}

    You MUST complete this step:

    Update your assets/js/app.js to import and register the CountdownTimer hook:

       Add to imports (near the top):
           import { CountdownTimer } from "./bankid_hooks"

       Add to Hooks object (before creating LiveSocket):
           Hooks.CountdownTimer = CountdownTimer

    Without this step, the countdown timer will NOT work!
    """)
  end

  defp add_routes(igniter, options) do
    router_module = Module.concat(options[:web_module], Router)

    routes_code = """
    # BankID authentication callback (stores token in session)
    get "/auth/callback", AuthCallbackController, :callback

    # BankID authentication LiveView
    live "/auth/user/bank_id", BankIDLive
    """

    igniter
    |> Igniter.Libs.Phoenix.append_to_scope(
      "/",
      routes_code,
      router: router_module,
      arg2: options[:web_module],
      with_pipelines: [:browser]
    )
  end

  defp find_repo(igniter) do
    app_name = Igniter.Project.Application.app_name(igniter)
    Module.concat([Macro.camelize(to_string(app_name)), Repo])
  end

  # Helper function to add an extension to the use Ash.Resource statement
  defp add_extension_to_use(zipper, extension_module) do
    with {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, Ash.Resource),
         {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
         {:ok, zipper} <- move_to_extensions_option(zipper) do
      # Get the current extensions list node
      current_node = Sourceror.Zipper.node(zipper)

      # Update the extensions list
      case current_node do
        # List node [AshAuthentication, ...]
        list when is_list(list) ->
          # Add our extension if not already present
          if Enum.any?(list, &matches_module?(&1, extension_module)) do
            {:ok, zipper}
          else
            new_list = list ++ [Sourceror.parse_string!(inspect(extension_module))]
            {:ok, Sourceror.Zipper.replace(zipper, new_list)}
          end

        _ ->
          {:ok, zipper}
      end
    else
      _ -> {:ok, zipper}
    end
  end

  defp move_to_extensions_option(zipper) do
    # Try to find the extensions: [...] option
    Igniter.Code.Keyword.get_key(zipper, :extensions)
  end

  defp matches_module?(node, module) do
    case node do
      {:__aliases__, _, parts} ->
        Module.concat(parts) == module

      _ ->
        false
    end
  end
end

end
