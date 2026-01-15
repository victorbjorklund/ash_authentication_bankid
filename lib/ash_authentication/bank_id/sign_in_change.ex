defmodule AshAuthentication.BankID.SignInChange do
  @moduledoc """
  Ash Resource Change that handles the BankID sign-in process.

  This change is applied to the sign-in create action and:
  1. Retrieves and validates the BankID order
  2. Extracts user information from the completed order
  3. Sets user attributes from BankID data
  4. Generates a JWT token after successful transaction

  This follows the exact pattern from AshAuthentication.Strategy.MagicLink.SignInChange.
  """

  use Ash.Resource.Change
  alias Ash.{Changeset, Query, Resource}
  alias AshAuthentication.{Errors, Info, Jwt}

  require Logger

  @doc false
  @impl true
  @spec change(Changeset.t(), keyword, Ash.Resource.Change.context()) :: Changeset.t()
  def change(changeset, opts, context) do
    case Info.find_strategy(changeset, context, opts) do
      {:ok, strategy} ->
        with {:got_order_ref, order_ref} when is_binary(order_ref) <-
               {:got_order_ref, Changeset.get_argument(changeset, :order_ref)},
             {:got_session_id, session_id} when is_binary(session_id) <-
               {:got_session_id, Changeset.get_argument(changeset, :session_id)},
             {:ok, order} <- get_and_validate_order(strategy, order_ref, session_id, context),
             {:ok, user_info} <- extract_and_validate_user_info(order.completion_data) do
          # Set user attributes from BankID data
          changeset
          |> Changeset.force_change_attribute(
            strategy.identity_field,
            user_info["personal_number"]
          )
          |> Changeset.force_change_attribute(
            strategy.personal_number_field,
            user_info["personal_number"]
          )
          |> Changeset.force_change_attribute(strategy.given_name_field, user_info["given_name"])
          |> Changeset.force_change_attribute(strategy.surname_field, user_info["surname"])
          |> Changeset.force_change_attribute(strategy.verified_at_field, DateTime.utc_now())
          |> Changeset.force_change_attribute(strategy.ip_address_field, order.ip_address)
          |> Changeset.after_transaction(fn _changeset, result ->
            case result do
              {:ok, record} ->
                # Mark order as consumed
                mark_order_consumed(order, context)

                # Generate JWT token (following MagicLink pattern)
                {:ok, token, _claims} =
                  Jwt.token_for_user(record, %{}, Ash.Context.to_opts(context))

                {:ok, Resource.put_metadata(record, :token, token)}

              other ->
                other
            end
          end)
        else
          {:got_order_ref, nil} ->
            add_error(changeset, "order_ref", "No order_ref provided")

          {:got_order_ref, other} ->
            add_error(
              changeset,
              "order_ref",
              "Expected order_ref to be a string, got: #{inspect(other)}"
            )

          {:got_session_id, nil} ->
            add_error(changeset, "session_id", "No session_id provided")

          {:got_session_id, other} ->
            add_error(
              changeset,
              "session_id",
              "Expected session_id to be a string, got: #{inspect(other)}"
            )

          {:error, :order_not_found} ->
            add_error(changeset, "order_ref", "Order not found or session mismatch")

          {:error, :order_not_complete} ->
            add_error(changeset, "order_ref", "Order is not complete yet")

          {:error, :order_already_consumed} ->
            add_error(changeset, "order_ref", "Order has already been used")

          {:error, :order_expired} ->
            add_error(changeset, "order_ref", "Order has expired")

          {:error, :completion_data_missing} ->
            add_error(changeset, "order_ref", "Order completion data is missing")

          {:error, :completion_data_invalid} ->
            add_error(changeset, "order_ref", "Order completion data is invalid")

          {:error, :invalid_user_info} ->
            add_error(
              changeset,
              "order_ref",
              "Could not extract user information from BankID response"
            )

          {:error, {:missing_user_info_fields, fields}} ->
            add_error(
              changeset,
              "order_ref",
              "Missing required user information: #{Enum.join(fields, ", ")}"
            )

          {:error, reason} ->
            add_error(changeset, "order_ref", "BankID authentication failed: #{inspect(reason)}")
        end

      {:error, _reason} ->
        add_error(changeset, :base, "No BankID strategy found")
    end
  end

  defp get_and_validate_order(strategy, order_ref, session_id, context) do
    require Ash.Query

    # Query by both order_ref AND session_id to prevent order hijacking
    # This ensures the caller owns the order they're trying to complete
    case strategy.order_resource
         |> Query.new()
         |> Ash.Query.filter(order_ref == ^order_ref and session_id == ^session_id)
         |> Ash.read_one(Ash.Context.to_opts(context)) do
      {:ok, nil} ->
        {:error, :order_not_found}

      {:ok, order} ->
        validate_order(order, strategy)

      {:error, reason} ->
        Logger.error("Failed to fetch BankID order: #{inspect(reason)}")
        {:error, :order_not_found}
    end
  end

  defp validate_order(order, strategy) do
    with :ok <- validate_order_status(order),
         :ok <- validate_order_expiration(order, strategy),
         :ok <- validate_completion_data(order) do
      {:ok, order}
    end
  end

  defp validate_order_status(%{status: "complete", consumed: false}), do: :ok
  defp validate_order_status(%{consumed: true}), do: {:error, :order_already_consumed}
  defp validate_order_status(_), do: {:error, :order_not_complete}

  defp validate_order_expiration(order, strategy) do
    # Orders should not be used after they expire
    # Use order_ttl from strategy configuration (default: 300 seconds)
    ttl_seconds = strategy.order_ttl || 300
    expiration_time = DateTime.add(order.updated_at, ttl_seconds, :second)

    if DateTime.compare(DateTime.utc_now(), expiration_time) == :gt do
      {:error, :order_expired}
    else
      :ok
    end
  end

  defp validate_completion_data(%{completion_data: nil}) do
    {:error, :completion_data_missing}
  end

  defp validate_completion_data(%{completion_data: data}) when is_map(data) do
    :ok
  end

  defp validate_completion_data(_) do
    {:error, :completion_data_invalid}
  end

  defp extract_and_validate_user_info(completion_data) do
    case BankID.extract_user_info(completion_data) do
      user_info when is_map(user_info) ->
        validate_user_info_fields(user_info)

      _ ->
        {:error, :invalid_user_info}
    end
  end

  defp validate_user_info_fields(user_info) do
    required_fields = ["personal_number", "given_name", "surname"]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        is_nil(user_info[field]) or user_info[field] == ""
      end)

    if Enum.empty?(missing_fields) do
      {:ok, user_info}
    else
      {:error, {:missing_user_info_fields, missing_fields}}
    end
  end

  defp mark_order_consumed(order, context) do
    # Mark the order as consumed to prevent reuse
    # Use bulk_update with filter to avoid BulkResult issues
    order.__struct__
    |> Query.new()
    |> Ash.Query.filter(id == ^order.id)
    |> Ash.bulk_update(:update, %{consumed: true}, Ash.Context.to_opts(context))
    |> case do
      %Ash.BulkResult{status: :success} ->
        Logger.debug("Marked BankID order #{order.order_ref} as consumed")
        :ok

      %Ash.BulkResult{errors: errors} ->
        Logger.error("Failed to mark BankID order as consumed: #{inspect(errors)}")
        :ok

      {:ok, _} ->
        Logger.debug("Marked BankID order #{order.order_ref} as consumed")
        :ok

      {:error, reason} ->
        Logger.error("Failed to mark BankID order as consumed: #{inspect(reason)}")
        :ok
    end
  end

  defp add_error(changeset, field, message) do
    Changeset.add_error(
      changeset,
      Errors.AuthenticationFailed.exception(
        field: field,
        message: message,
        caused_by: %{module: __MODULE__}
      )
    )
  end
end
