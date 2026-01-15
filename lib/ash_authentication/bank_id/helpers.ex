defmodule AshAuthentication.BankID.Helpers do
  @moduledoc """
  Helper functions for BankID LiveView implementations.

  This module provides utility functions commonly needed when building
  BankID authentication flows in Phoenix LiveView.
  """

  @poll_interval 2_000
  @renewal_interval 28_000
  @qr_update_interval 1_000

  @doc """
  Generates a cryptographically secure random session ID.

  Returns a URL-safe base64-encoded string of 32 random bytes.

  ## Examples

      iex> session_id = AshAuthentication.BankID.Helpers.generate_session_id()
      iex> is_binary(session_id)
      true
      iex> byte_size(session_id) > 40
      true
  """
  @spec generate_session_id() :: String.t()
  def generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Schedules a BankID status poll after the configured interval.

  Sends a `:poll_status` message to the current process after #{@poll_interval}ms (2 seconds).
  This adheres to BankID's requirement to poll at least 2 seconds apart.

  ## Examples

      iex> AshAuthentication.BankID.Helpers.schedule_poll()
      :ok
  """
  @spec schedule_poll() :: :ok
  def schedule_poll do
    Process.send_after(self(), :poll_status, @poll_interval)
    :ok
  end

  @doc """
  Schedules a BankID order renewal after the configured interval.

  Sends a `:renew_order` message to the current process after #{@renewal_interval}ms (28 seconds).
  Orders are renewed before BankID's 30-second timeout to maintain authentication sessions.

  ## Examples

      iex> AshAuthentication.BankID.Helpers.schedule_renewal()
      :ok
  """
  @spec schedule_renewal() :: :ok
  def schedule_renewal do
    Process.send_after(self(), :renew_order, @renewal_interval)
    :ok
  end

  @doc """
  Schedules a QR code content update after the configured interval.

  Sends an `:update_qr_content` message to the current process after #{@qr_update_interval}ms (1 second).
  QR codes must be regenerated every second using BankID's time-based HMAC algorithm.

  ## Examples

      iex> AshAuthentication.BankID.Helpers.schedule_qr_update()
      :ok
  """
  @spec schedule_qr_update() :: :ok
  def schedule_qr_update do
    Process.send_after(self(), :update_qr_content, @qr_update_interval)
    :ok
  end

  @doc """
  Returns the poll interval in milliseconds.

  ## Examples

      iex> AshAuthentication.BankID.Helpers.poll_interval()
      2000
  """
  @spec poll_interval() :: pos_integer()
  def poll_interval, do: @poll_interval

  @doc """
  Returns the renewal interval in milliseconds.

  ## Examples

      iex> AshAuthentication.BankID.Helpers.renewal_interval()
      28000
  """
  @spec renewal_interval() :: pos_integer()
  def renewal_interval, do: @renewal_interval

  @doc """
  Returns the QR update interval in milliseconds.

  ## Examples

      iex> AshAuthentication.BankID.Helpers.qr_update_interval()
      1000
  """
  @spec qr_update_interval() :: pos_integer()
  def qr_update_interval, do: @qr_update_interval
end
