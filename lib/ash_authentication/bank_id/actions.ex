defmodule AshAuthentication.BankID.Actions do
  @moduledoc """
  Business logic for BankID authentication actions.

  This module provides the code interface for executing BankID authentication
  actions on user resources. It follows the same pattern as MagicLink.Actions.

  Only the sign_in action is defined here, as initiate and poll are pure HTTP
  operations handled entirely by plugs.
  """

  alias Ash.{Changeset, Resource}
  alias AshAuthentication.{BankID, Errors, Info}

  @doc """
  Sign in or register a user using BankID authentication.

  This function calls the auto-generated sign_in action (CREATE with upsert)
  on the user resource. The SignInChange handles the actual BankID processing.

  ## Parameters

  - `strategy` - The BankID strategy configuration
  - `params` - Parameters including the `order_ref`
  - `options` - Options including context, tenant, etc.

  ## Returns

  - `{:ok, user}` - User record with JWT token in metadata
  - `{:error, error}` - Authentication failed error

  ## Examples

      iex> Actions.sign_in(strategy, %{"order_ref" => "abc123"}, [])
      {:ok, %User{...}}
  """
  @spec sign_in(BankID.t(), map, keyword) ::
          {:ok, Resource.record()} | {:error, Errors.AuthenticationFailed.t()}
  def sign_in(strategy, params, options) do
    options =
      options
      |> Keyword.put_new_lazy(:domain, fn -> Info.domain!(strategy.resource) end)

    # Call the auto-generated sign_in action (CREATE with upsert)
    strategy.resource
    |> Changeset.new()
    |> Changeset.set_context(%{private: %{ash_authentication?: true}})
    |> Changeset.for_create(strategy.sign_in_action_name, params, options)
    |> Ash.create()
    |> case do
      {:ok, record} ->
        {:ok, record}

      {:error, error} ->
        {:error,
         Errors.AuthenticationFailed.exception(
           strategy: strategy,
           caused_by: error
         )}
    end
  end
end
