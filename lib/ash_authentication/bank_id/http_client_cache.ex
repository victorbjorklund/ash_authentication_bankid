defmodule AshAuthentication.BankID.HTTPClientCache do
  @moduledoc """
  Cache for BankID HTTPClient to avoid re-reading and decoding certificates on every request.

  This module uses `:persistent_term` to cache the HTTPClient globally after first initialization.
  The client is created once on first use and reused for all subsequent requests.

  ## Performance Impact

  Without caching:
  - Every BankID API request reads 3 certificate files from disk
  - Every request decodes PEM to DER format
  - Significant I/O and CPU overhead

  With caching:
  - Certificates loaded once on first request
  - All subsequent requests use cached client
  - Near-zero overhead for certificate handling

  ## Usage

      # Get cached client (initializes on first call)
      client = AshAuthentication.BankID.HTTPClientCache.get()

      # Use with BankID functions
      {:ok, auth} = BankID.authenticate(ip, http_client: client)
  """

  @cache_key {__MODULE__, :http_client}

  @doc """
  Get the cached HTTPClient, initializing it if needed.

  The client is initialized once on first call and cached globally using `:persistent_term`.
  Subsequent calls return the cached instance with zero overhead.

  ## Returns

  `BankID.HTTPClient.t()` - The cached HTTP client instance
  """
  @spec get() :: BankID.HTTPClient.t()
  def get do
    case :persistent_term.get(@cache_key, nil) do
      nil -> initialize()
      client -> client
    end
  end

  @doc """
  Clear the cached HTTPClient.

  This is primarily useful for testing or when certificate configuration changes.
  In production, you typically never need to call this.
  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.erase(@cache_key)
    :ok
  end

  # Private function to initialize and cache the client
  defp initialize do
    client = BankID.HTTPClient.new()
    :persistent_term.put(@cache_key, client)
    client
  end
end
