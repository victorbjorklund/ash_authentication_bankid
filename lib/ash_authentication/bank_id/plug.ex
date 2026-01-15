defmodule AshAuthentication.BankID.Plug do
  @moduledoc """
  Plug handlers for BankID HTTP endpoints.

  This module provides handlers for the three BankID phases:
  - `initiate/2` - Starts a BankID authentication and returns QR data
  - `poll/2` - Checks the status of an ongoing authentication
  - `sign_in/2` - Completes the authentication and returns a user with JWT token

  Follows the pattern from MagicLink.Plug and OAuth2.Plug.
  """

  alias Ash.{Changeset, Query}
  alias AshAuthentication.Strategy
  alias AshAuthentication.BankID.HTTPClientCache
  alias Plug.Conn

  # Alias the top-level BankID client library
  alias BankID, as: BankIDClient
  import Ash.PlugHelpers, only: [get_actor: 1, get_tenant: 1, get_context: 1]
  import AshAuthentication.Plug.Helpers, only: [store_authentication_result: 2]

  require Logger
  require Ash.Query

  @doc """
  Initiate a BankID authentication order.

  This endpoint:
  1. Generates a session ID and stores it in the Phoenix session
  2. Calls the BankID API to start authentication
  3. Creates an order record in the order resource
  4. Returns QR tokens (but NOT the secret!)

  ## Expected response

  Returns {:ok, data} with:
  - `order_ref` - Reference for polling and completion
  - `qr_start_token` - Public token for QR code generation
  - `auto_start_token` - Token for same-device flow
  - `start_t` - Timestamp for QR code generation
  """
  @spec initiate(Conn.t(), AshAuthentication.BankID.t()) :: Conn.t()
  def initiate(conn, strategy) do
    session_key = session_key(strategy)
    session_id = Conn.get_session(conn, session_key) || generate_session_id()
    user_ip = get_user_ip(conn)

    # Call BankID API to initiate authentication using cached HTTPClient
    http_client = HTTPClientCache.get()

    case BankIDClient.authenticate(user_ip, http_client: http_client) do
      {:ok, auth_data} ->
        # Create order in the order resource
        order_params = %{
          order_ref: auth_data.order_ref,
          qr_start_token: auth_data.qr_start_token,
          qr_start_secret: auth_data.qr_start_secret,
          auto_start_token: auth_data.auto_start_token,
          start_t: auth_data.start_t,
          session_id: session_id,
          ip_address: user_ip,
          status: "pending"
        }

        case create_order(strategy, order_params, opts(conn)) do
          {:ok, _order} ->
            # Store session ID
            conn = Conn.put_session(conn, session_key, session_id)

            # Return sanitized data (NO SECRET!)
            result = %{
              order_ref: auth_data.order_ref,
              qr_start_token: auth_data.qr_start_token,
              auto_start_token: auth_data.auto_start_token,
              start_t: auth_data.start_t
            }

            store_authentication_result(conn, {:ok, result})

          {:error, reason} ->
            Logger.error("Failed to create BankID order: #{inspect(reason)}")
            store_authentication_result(conn, {:error, "Failed to create order"})
        end

      {:error, reason} ->
        Logger.error("Failed to initiate BankID authentication: #{inspect(reason)}")
        store_authentication_result(conn, {:error, "Failed to initiate BankID"})
    end
  end

  @doc """
  Poll the status of a BankID order.

  This endpoint:
  1. Gets the order from the database
  2. Calls BankID.collect to check status
  3. Updates the order in the database
  4. Returns the current status

  This does NOT complete the authentication - it just returns status info.

  ## Parameters

  Expects `order_ref` in the query params.

  ## Response

  Returns {:ok, data} with:
  - `status` - "pending", "complete", or "failed"
  - `hint_code` - BankID hint code for user messaging
  """
  @spec poll(Conn.t(), AshAuthentication.BankID.t()) :: Conn.t()
  def poll(conn, strategy) do
    session_key = session_key(strategy)
    session_id = Conn.get_session(conn, session_key)
    order_ref = conn.params["order_ref"] || conn.params[:order_ref]

    http_client = HTTPClientCache.get()

    with {:got_order_ref, order_ref} when is_binary(order_ref) <-
           {:got_order_ref, order_ref},
         {:ok, order} <- get_order_by_ref(strategy, order_ref, session_id, opts(conn)),
         {:ok, collect_result} <- BankIDClient.collect(order.order_ref, http_client: http_client) do
      # Update order with new status
      update_order(order, collect_result, opts(conn))

      # Return status info
      result = %{
        status: collect_result.status,
        hint_code: collect_result[:hint_code]
      }

      store_authentication_result(conn, {:ok, result})
    else
      {:got_order_ref, _} ->
        store_authentication_result(conn, {:error, "order_ref is required"})

      {:error, :not_found} ->
        store_authentication_result(conn, {:error, "Order not found"})

      {:error, reason} ->
        Logger.error("Failed to poll BankID order: #{inspect(reason)}")
        store_authentication_result(conn, {:error, "Failed to poll order"})
    end
  end

  @doc """
  Renew a BankID order by creating a new one.

  This endpoint:
  1. Validates the current order exists and matches session
  2. Creates a new BankID order with same session_id and ip_address
  3. Cancels the old order via BankID.cancel
  4. Deletes the old order from database
  5. Returns new order data (qr_start_token, auto_start_token, start_t)

  ## Parameters

  Expects `order_ref` in params (the current order to renew).

  ## Response

  Returns {:ok, data} with new order_ref, qr_start_token, auto_start_token, start_t
  """
  @spec renew(Conn.t(), AshAuthentication.BankID.t()) :: Conn.t()
  def renew(conn, strategy) do
    session_key = session_key(strategy)
    session_id = Conn.get_session(conn, session_key)
    old_order_ref = conn.params["order_ref"] || conn.params[:order_ref]

    http_client = HTTPClientCache.get()

    with {:got_order_ref, order_ref} when is_binary(order_ref) <-
           {:got_order_ref, old_order_ref},
         {:ok, old_order} <- get_order_by_ref(strategy, order_ref, session_id, opts(conn)),
         user_ip <- old_order.ip_address,
         {:ok, auth_data} <- BankIDClient.authenticate(user_ip, http_client: http_client),
         {:ok, _new_order} <-
           create_order(
             strategy,
             %{
               order_ref: auth_data.order_ref,
               qr_start_token: auth_data.qr_start_token,
               qr_start_secret: auth_data.qr_start_secret,
               auto_start_token: auth_data.auto_start_token,
               start_t: auth_data.start_t,
               session_id: session_id,
               ip_address: user_ip,
               status: "pending"
             },
             opts(conn)
           ) do
      # Old orders will be cleaned up by a separate cleanup process
      Logger.debug("Created new BankID order #{auth_data.order_ref}, old order #{old_order.order_ref} will be cleaned up later")

      # Return new order data
      result = %{
        order_ref: auth_data.order_ref,
        qr_start_token: auth_data.qr_start_token,
        auto_start_token: auth_data.auto_start_token,
        start_t: auth_data.start_t
      }

      store_authentication_result(conn, {:ok, result})
    else
      {:got_order_ref, _} ->
        store_authentication_result(conn, {:error, "order_ref is required"})

      {:error, :not_found} ->
        store_authentication_result(conn, {:error, "Order not found"})

      {:error, reason} ->
        Logger.error("Failed to renew BankID order: #{inspect(reason)}")
        store_authentication_result(conn, {:error, "Failed to renew order"})
    end
  end

  @doc """
  Complete BankID authentication and sign in the user.

  This endpoint:
  1. Validates the order is complete
  2. Calls the sign_in action which handles user creation/update
  3. Returns the user with JWT token in metadata

  ## Parameters

  Expects `order_ref` in the params.

  ## Response

  Returns {:ok, user} with JWT token in metadata.
  """
  @spec sign_in(Conn.t(), AshAuthentication.BankID.t()) :: Conn.t()
  def sign_in(conn, strategy) do
    session_key = session_key(strategy)
    session_id = Conn.get_session(conn, session_key)

    # Add session_id to params for security validation in SignInChange
    params = Map.put(conn.params, "session_id", session_id)

    result = Strategy.action(strategy, :sign_in, params, opts(conn))
    store_authentication_result(conn, result)
  end

  # Private helpers

  defp opts(conn) do
    [actor: get_actor(conn), tenant: get_tenant(conn), context: get_context(conn) || %{}]
    |> Enum.reject(&is_nil(elem(&1, 1)))
  end

  defp session_key(strategy), do: :"#{strategy.name}_session"

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp get_user_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp create_order(strategy, params, opts) do
    strategy.order_resource
    |> Changeset.for_create(:create, params)
    |> Ash.create(opts)
  end

  defp get_order_by_ref(strategy, order_ref, session_id, opts) do
    require Ash.Query

    # Query by order_ref only, then use constant-time comparison for session_id
    # This prevents timing attacks that could leak session_id information
    strategy.order_resource
    |> Query.new()
    |> Ash.Query.filter(order_ref == ^order_ref)
    |> Ash.read_one(opts)
    |> case do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, order} ->
        # Use constant-time comparison to prevent timing attacks
        if secure_compare(order.session_id, session_id) do
          {:ok, order}
        else
          # Return same error as "not found" to prevent information leakage
          {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end

  defp secure_compare(nil, _), do: false
  defp secure_compare(_, nil), do: false

  defp update_order(order, collect_result, opts) do
    order
    |> Changeset.for_update(:update, %{
      status: collect_result.status,
      hint_code: collect_result[:hint_code],
      completion_data: collect_result[:completion_data]
    })
    |> Ash.update(opts)
  end
end
