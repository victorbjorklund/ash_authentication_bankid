defmodule AshAuthentication.BankID.Transformer do
  @moduledoc """
  DSL transformer for the BankID authentication strategy.

  This transformer runs at compile time to:
  1. Set default action names
  2. Build the sign-in action with upsert configuration
  3. Register the strategy actions
  """

  alias Ash.Resource
  alias AshAuthentication.BankID
  alias Spark.Dsl.Transformer
  import AshAuthentication.Strategy.Custom.Helpers
  import AshAuthentication.Validations
  import AshAuthentication.Utils

  @doc false
  @spec transform(BankID.t(), map) :: {:ok, BankID.t() | map} | {:error, any}
  def transform(strategy, dsl_state) do
    with :ok <-
           validate_token_generation_enabled(
             dsl_state,
             "Token generation must be enabled for BankID authentication to work."
           ),
         strategy <- maybe_set_sign_in_action_name(strategy),
         {:ok, dsl_state} <-
           maybe_build_action(
             dsl_state,
             strategy.sign_in_action_name,
             &build_sign_in_action(&1, strategy)
           ) do
      dsl_state =
        dsl_state
        |> then(&register_strategy_actions([strategy.sign_in_action_name], &1, strategy))
        |> put_strategy(strategy)

      {:ok, dsl_state}
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp maybe_set_sign_in_action_name(strategy) when is_nil(strategy.sign_in_action_name),
    do: %{strategy | sign_in_action_name: String.to_atom("sign_in_with_#{strategy.name}")}

  defp maybe_set_sign_in_action_name(strategy), do: strategy

  defp build_sign_in_action(dsl_state, strategy) do
    # Build CREATE action with upsert (similar to MagicLink)
    arguments = [
      Transformer.build_entity!(Resource.Dsl, [:actions, :create], :argument,
        name: :order_ref,
        type: :string,
        allow_nil?: false,
        description: "The BankID order reference to complete authentication for"
      ),
      Transformer.build_entity!(Resource.Dsl, [:actions, :create], :argument,
        name: :session_id,
        type: :string,
        allow_nil?: false,
        description: "The session ID to validate ownership of the order"
      )
    ]

    changes = [
      Transformer.build_entity!(Resource.Dsl, [:actions, :create], :change,
        change: BankID.SignInChange,
        description: "Processes the BankID authentication and generates a JWT token"
      )
    ]

    metadata = [
      Transformer.build_entity!(Resource.Dsl, [:actions, :create], :metadata,
        name: :token,
        type: :string,
        allow_nil?: false,
        description: "A JWT that can be used to authenticate the user"
      )
    ]

    # Find the identity for upsert
    identity =
      Enum.find(Ash.Resource.Info.identities(dsl_state), fn identity ->
        identity.keys == [strategy.identity_field]
      end)

    unless identity do
      raise """
      No identity found for field #{inspect(strategy.identity_field)} on resource #{inspect(strategy.resource)}.

      You must define an identity on the #{inspect(strategy.identity_field)} field for BankID authentication to work.

      Example:

          identities do
            identity :unique_personal_number, [:#{strategy.identity_field}]
          end
      """
    end

    Transformer.build_entity(Resource.Dsl, [:actions], :create,
      name: strategy.sign_in_action_name,
      description: "Sign in or register a user with BankID authentication.",
      arguments: arguments,
      changes: changes,
      metadata: metadata,
      upsert?: true,
      upsert_identity: identity.name,
      upsert_fields: [strategy.identity_field]
    )
  end
end
