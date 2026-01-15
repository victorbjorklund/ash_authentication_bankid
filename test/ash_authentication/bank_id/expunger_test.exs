defmodule AshAuthentication.BankID.ExpungerTest do
  use ExUnit.Case, async: false

  alias AshAuthentication.BankID.Expunger

  # Mock order resource modules for testing
  defmodule TestOrderResource do
    @moduledoc false
  end

  defmodule TestOrderResource2 do
    @moduledoc false
  end

  defmodule TestOrderResource3 do
    @moduledoc false
  end

  defmodule TestOrderResource4 do
    @moduledoc false
  end

  # Note: These are basic structure tests.
  # Full integration tests require a real Ash resource and database setup.
  # Those tests should be in the consuming application (e.g., pet_water).

  describe "Expunger initialization" do
    test "starts with valid configuration" do
      opts = [
        order_resource: TestOrderResource,
        order_ttl: 300,
        cleanup_interval: 5000,
        consumed_order_ttl: 86_400,
        name: :test_expunger
      ]

      {:ok, pid} = start_supervised({Expunger, opts})
      assert Process.alive?(pid)
    end

    test "requires order_resource option" do
      opts = [
        order_ttl: 300,
        name: :test_expunger_no_resource
      ]

      Process.flag(:trap_exit, true)

      {:error, {{%KeyError{key: :order_resource}, _stacktrace}, _}} =
        start_supervised({Expunger, opts})
    end

    test "requires order_ttl option" do
      opts = [
        order_resource: TestOrderResource2,
        name: :test_expunger_no_ttl
      ]

      Process.flag(:trap_exit, true)

      {:error, {{%KeyError{key: :order_ttl}, _stacktrace}, _}} =
        start_supervised({Expunger, opts})
    end

    test "uses default values for optional configuration" do
      opts = [
        order_resource: TestOrderResource3,
        order_ttl: 300,
        name: :test_expunger_defaults
      ]

      {:ok, pid} = start_supervised({Expunger, opts})
      assert Process.alive?(pid)

      # The GenServer should be running with default cleanup_interval and consumed_order_ttl
      state = :sys.get_state(pid)
      assert state.cleanup_interval == 300_000  # 5 minutes
      assert state.consumed_ttl == 86_400  # 24 hours
    end
  end

  describe "trigger_cleanup/1" do
    test "can be called manually without errors" do
      opts = [
        order_resource: TestOrderResource4,
        order_ttl: 300,
        cleanup_interval: 60_000,
        name: :test_expunger_manual
      ]

      {:ok, _pid} = start_supervised({Expunger, opts})

      # Should not raise
      assert :ok = Expunger.trigger_cleanup(:test_expunger_manual)
    end
  end

  # Note: Full integration tests with actual order cleanup require:
  # 1. A real Ash resource with OrderResource extension
  # 2. A database (via AshPostgres or similar)
  # 3. Test setup to create orders with specific timestamps
  # 4. Assertions on database state after cleanup
  #
  # These tests should be written in the demo application (pet_water)
  # where the full infrastructure is available.
end
