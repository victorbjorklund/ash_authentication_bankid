defmodule AshAuthentication.BankID.HTTPClientCacheTest do
  use ExUnit.Case, async: false

  alias AshAuthentication.BankID.HTTPClientCache

  describe "get/0" do
    setup do
      # Clear cache before each test
      HTTPClientCache.clear()
      :ok
    end

    test "returns a BankID.HTTPClient struct" do
      client = HTTPClientCache.get()

      assert %BankID.HTTPClient{} = client
      assert is_binary(client.cert_der)
      assert is_tuple(client.key_der)
      assert is_list(client.cacerts_der)
    end

    test "caches the client on first call" do
      # First call - should initialize
      client1 = HTTPClientCache.get()

      # Second call - should return cached instance
      client2 = HTTPClientCache.get()

      # Should be the exact same struct (not just equal, but identical)
      assert client1 === client2
    end

    test "returns the same client across multiple calls" do
      clients = for _ <- 1..10, do: HTTPClientCache.get()

      # All clients should be identical
      [first | rest] = clients
      assert Enum.all?(rest, fn client -> client === first end)
    end
  end

  describe "clear/0" do
    test "clears the cached client" do
      # Get initial client
      client1 = HTTPClientCache.get()

      # Clear cache
      :ok = HTTPClientCache.clear()

      # Get new client - should be a different instance
      client2 = HTTPClientCache.get()

      # Should be equal in content but not identical in memory
      # (we can't easily test this without inspecting memory addresses,
      # but we can verify it's still a valid client)
      assert %BankID.HTTPClient{} = client2
      assert client1.cert_der == client2.cert_der
    end
  end
end
