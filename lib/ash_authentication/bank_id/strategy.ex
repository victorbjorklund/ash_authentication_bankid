defimpl AshAuthentication.Strategy, for: AshAuthentication.BankID do
  @moduledoc """
  Implementation of the AshAuthentication.Strategy protocol for BankID.

  This module defines how the BankID strategy integrates with the Ash Authentication
  framework, including HTTP routing, phases, and action delegation.
  """

  alias AshAuthentication.{BankID, Info}

  @doc "Returns the strategy name"
  @spec name(BankID.t()) :: atom
  def name(strategy), do: strategy.name

  @doc """
  Returns the phases supported by this strategy.

  Phases represent HTTP endpoints:
  - `:initiate` - POST endpoint to start BankID authentication
  - `:poll` - GET endpoint to check order status
  - `:renew` - POST endpoint to renew an order
  - `:sign_in` - POST endpoint to complete authentication

  Note: Only `:sign_in` is an actual Ash action on the user resource.
  `:initiate`, `:poll`, and `:renew` are HTTP-only endpoints.
  """
  @spec phases(BankID.t()) :: [AshAuthentication.Strategy.phase()]
  def phases(_strategy), do: [:initiate, :poll, :renew, :sign_in]

  @doc """
  Returns the Ash actions on the user resource.

  Only `:sign_in` is an actual Ash action (CREATE with upsert).
  The other phases are handled purely via HTTP plugs.
  """
  @spec actions(BankID.t()) :: [AshAuthentication.Strategy.action()]
  def actions(_strategy), do: [:sign_in]

  @doc """
  Returns the HTTP method for each phase.

  - `:poll` uses GET (read-only status check)
  - All others use POST
  """
  @spec method_for_phase(BankID.t(), AshAuthentication.Strategy.phase()) ::
          AshAuthentication.Strategy.http_method()
  def method_for_phase(_strategy, :poll), do: :get
  def method_for_phase(_strategy, :renew), do: :post
  def method_for_phase(_strategy, _phase), do: :post

  @doc """
  Returns the HTTP routes for this strategy.

  Routes are generated based on the subject name and strategy name.
  For example, if the subject name is "user" and strategy name is "bank_id":

  - POST /user/bank_id/initiate - Start authentication
  - GET /user/bank_id/poll - Check status
  - POST /user/bank_id/renew - Renew order
  - POST /user/bank_id - Complete authentication
  """
  @spec routes(BankID.t()) :: [AshAuthentication.Strategy.route()]
  def routes(strategy) do
    subject_name = Info.authentication_subject_name!(strategy.resource)

    [
      {"/#{subject_name}/#{strategy.name}/initiate", :initiate},
      {"/#{subject_name}/#{strategy.name}/poll", :poll},
      {"/#{subject_name}/#{strategy.name}/renew", :renew},
      {"/#{subject_name}/#{strategy.name}", :sign_in}
    ]
  end

  @doc """
  Delegates to the appropriate plug handler for each phase.
  """
  @spec plug(BankID.t(), AshAuthentication.Strategy.phase(), Plug.Conn.t()) :: Plug.Conn.t()
  def plug(strategy, :initiate, conn), do: BankID.Plug.initiate(conn, strategy)
  def plug(strategy, :poll, conn), do: BankID.Plug.poll(conn, strategy)
  def plug(strategy, :renew, conn), do: BankID.Plug.renew(conn, strategy)
  def plug(strategy, :sign_in, conn), do: BankID.Plug.sign_in(conn, strategy)

  @doc """
  Delegates to the appropriate action handler.

  Only `:sign_in` is implemented as it's the only actual Ash action.
  """
  @spec action(BankID.t(), AshAuthentication.Strategy.action(), map, keyword) ::
          :ok | {:ok, Ash.Resource.record()} | {:error, any}
  def action(strategy, :sign_in, params, options),
    do: BankID.Actions.sign_in(strategy, params, options)

  @doc """
  Indicates that this strategy requires JWT tokens.
  """
  @spec tokens_required?(BankID.t()) :: true
  def tokens_required?(_strategy), do: true
end
