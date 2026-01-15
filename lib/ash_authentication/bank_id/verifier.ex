defmodule AshAuthentication.BankID.Verifier do
  @moduledoc """
  Verifier for the BankID authentication strategy.

  Validates that the user resource and order resource are properly configured
  for BankID authentication.
  """

  alias AshAuthentication.BankID
  alias Ash.Resource
  alias Spark.Error.DslError

  @doc false
  @spec verify(BankID.t(), map) :: :ok | {:error, Exception.t()}
  def verify(strategy, dsl_state) do
    with :ok <- validate_order_resource_exists(strategy),
         :ok <- validate_identity_field_exists(strategy, dsl_state),
         :ok <- validate_required_fields_exist(strategy, dsl_state),
         :ok <- validate_tokens_enabled(dsl_state) do
      :ok
    end
  end

  defp validate_order_resource_exists(%{order_resource: nil} = strategy) do
    {:error,
     DslError.exception(
       path: [:authentication, :strategies, strategy.name],
       message: """
       The `order_resource` option is required for BankID authentication.

       You must create an Ash resource to track BankID orders and configure it here.

       Example:

           bank_id do
             order_resource MyApp.Accounts.BankIDOrder
           end

       See AshAuthentication.BankID.OrderResource for details on creating the order resource.
       """
     )}
  end

  defp validate_order_resource_exists(_strategy), do: :ok

  defp validate_identity_field_exists(strategy, dsl_state) do
    case Resource.Info.attribute(dsl_state, strategy.identity_field) do
      nil ->
        {:error,
         DslError.exception(
           path: [:authentication, :strategies, strategy.name],
           message: """
           The identity field #{inspect(strategy.identity_field)} does not exist on the resource.

           Add the #{inspect(strategy.identity_field)} attribute to your user resource:

               attributes do
                 attribute :#{strategy.identity_field}, :string do
                   allow_nil? false
                   public? true
                 end
               end

               identities do
                 identity :unique_#{strategy.identity_field}, [:#{strategy.identity_field}]
               end
           """
         )}

      _attribute ->
        :ok
    end
  end

  defp validate_required_fields_exist(strategy, dsl_state) do
    required_fields = [
      strategy.personal_number_field,
      strategy.given_name_field,
      strategy.surname_field,
      strategy.verified_at_field,
      strategy.ip_address_field
    ]

    missing_fields =
      Enum.reject(required_fields, fn field ->
        Resource.Info.attribute(dsl_state, field) != nil
      end)

    case missing_fields do
      [] ->
        :ok

      fields ->
        {:error,
         DslError.exception(
           path: [:authentication, :strategies, strategy.name],
           message: """
           The following required fields are missing from the user resource: #{inspect(fields)}

           Add these attributes to your user resource:

               attributes do
                 attribute :personal_number, :string, allow_nil?: false, public?: true
                 attribute :given_name, :string, allow_nil?: true, public?: true
                 attribute :surname, :string, allow_nil?: true, public?: true
                 attribute :bankid_verified_at, :utc_datetime_usec, allow_nil?: true
                 attribute :ip_address, :string, allow_nil?: true
               end
           """
         )}
    end
  end

  defp validate_tokens_enabled(dsl_state) do
    if AshAuthentication.Info.authentication_tokens_enabled?(dsl_state) do
      :ok
    else
      {:error,
       DslError.exception(
         path: [:authentication],
         message: """
         Token generation must be enabled for BankID authentication to work.

         Add tokens configuration to your user resource:

             authentication do
               tokens do
                 enabled? true
                 token_resource MyApp.Accounts.Token
                 signing_secret MyApp.Secrets
               end
             end
         """
       )}
    end
  end
end
