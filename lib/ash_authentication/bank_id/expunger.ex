defmodule AshAuthentication.BankID.Expunger do
  @moduledoc """
  GenServer that periodically cleans up expired and consumed BankID orders.

  This process prevents the indefinite accumulation of orders in the database
  by deleting:
  - Orders that have exceeded their TTL (expired)
  - Consumed orders that are older than the retention period

  ## Configuration

  The Expunger is configured through the BankID strategy DSL:

      bank_id do
        order_resource MyApp.Accounts.BankIDOrder
        cleanup_interval 300_000  # 5 minutes in milliseconds
        consumed_order_ttl 86_400  # 24 hours in seconds
      end

  Configuration options:
  - `cleanup_interval`: How often to run cleanup (default: 5 minutes)
  - `order_ttl`: How long orders are valid (inherited from strategy)
  - `consumed_order_ttl`: How long to retain consumed orders (default: 24 hours)

  ## Usage

  The Expunger should be added to your application's supervision tree:

      children = [
        # ... other children
        {AshAuthentication.BankID.Expunger,
         order_resource: MyApp.Accounts.BankIDOrder,
         order_ttl: 300,
         cleanup_interval: 300_000,
         consumed_order_ttl: 86_400}
      ]

  ## Manual Cleanup

  You can trigger a manual cleanup (useful for testing):

      AshAuthentication.BankID.Expunger.trigger_cleanup()
  """

  use GenServer
  require Logger
  require Ash.Query

  @default_cleanup_interval :timer.minutes(5)
  @default_consumed_ttl 86_400  # 24 hours in seconds

  ## Client API

  @doc """
  Starts the Expunger GenServer.

  ## Options

  - `:order_resource` (required) - The Ash resource module for BankID orders
  - `:order_ttl` (required) - Order TTL in seconds
  - `:cleanup_interval` (optional) - Cleanup interval in milliseconds
  - `:consumed_order_ttl` (optional) - Consumed order retention in seconds
  - `:name` (optional) - GenServer name (defaults to __MODULE__)
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Manually trigger a cleanup (useful for testing).
  """
  def trigger_cleanup(name \\ __MODULE__) do
    GenServer.cast(name, :cleanup)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    order_resource = Keyword.fetch!(opts, :order_resource)
    order_ttl = Keyword.fetch!(opts, :order_ttl)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    consumed_ttl = Keyword.get(opts, :consumed_order_ttl, @default_consumed_ttl)

    # Schedule first cleanup
    schedule_cleanup(cleanup_interval)

    Logger.info(
      "[BankID.Expunger] Started for #{inspect(order_resource)} " <>
      "with cleanup interval: #{cleanup_interval}ms"
    )

    {:ok, %{
      order_resource: order_resource,
      order_ttl: order_ttl,
      cleanup_interval: cleanup_interval,
      consumed_ttl: consumed_ttl
    }}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup(state)
    schedule_cleanup(state.cleanup_interval)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    perform_cleanup(state)
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp perform_cleanup(state) do
    Logger.debug("[BankID.Expunger] Starting cleanup for #{inspect(state.order_resource)}")

    # Calculate cutoff times
    now = DateTime.utc_now()
    expired_cutoff = DateTime.add(now, -state.order_ttl, :second)
    consumed_cutoff = DateTime.add(now, -state.consumed_ttl, :second)

    # Perform cleanup with a single query using OR logic
    total_count = cleanup_old_orders(state.order_resource, expired_cutoff, consumed_cutoff)

    Logger.info(
      "[BankID.Expunger] Cleanup completed for #{inspect(state.order_resource)}: " <>
      "#{total_count} orders deleted"
    )

    :ok
  rescue
    error ->
      Logger.error(
        "[BankID.Expunger] Cleanup failed for #{inspect(state.order_resource)}: " <>
        "#{inspect(error)}\n#{Exception.format_stacktrace()}"
      )
      :error
  end

  defp cleanup_old_orders(order_resource, expired_cutoff, consumed_cutoff) do
    # Delete orders with a single query using OR logic:
    # - Expired orders: updated_at < expired_cutoff AND consumed = false
    # - Old consumed orders: updated_at < consumed_cutoff AND consumed = true
    case order_resource
         |> Ash.Query.filter(
           (updated_at < ^expired_cutoff and consumed == false) or
           (updated_at < ^consumed_cutoff and consumed == true)
         )
         |> Ash.bulk_destroy(:destroy, %{},
              return_records?: false,
              return_errors?: true,
              authorize?: false) do
      %Ash.BulkResult{status: :success, records: nil} = result ->
        # When return_records? is false, we can't count from records
        # The count might be in result metadata depending on Ash version
        Map.get(result, :count, 0)

      %Ash.BulkResult{status: :success, records: records} when is_list(records) ->
        length(records)

      %Ash.BulkResult{errors: errors} ->
        Logger.warning(
          "[BankID.Expunger] Errors during order cleanup: #{inspect(errors)}"
        )
        0

      {:error, reason} ->
        Logger.warning(
          "[BankID.Expunger] Failed to cleanup orders: #{inspect(reason)}"
        )
        0
    end
  rescue
    error ->
      Logger.warning(
        "[BankID.Expunger] Exception during order cleanup: #{inspect(error)}"
      )
      0
  end
end
