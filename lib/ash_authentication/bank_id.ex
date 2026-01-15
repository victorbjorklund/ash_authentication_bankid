defmodule AshAuthentication.BankID do
  @moduledoc """
  Strategy for authentication using Swedish BankID.

  This authentication strategy provides integration with Swedish BankID,
  supporting both QR code (cross-device) and same-device authentication flows.

  ## Features

  - QR code-based authentication for desktop users
  - Same-device authentication for mobile users
  - Automatic user creation/update via upsert pattern
  - Session binding for security
  - Order expiration and cleanup

  ## Configuration

  Configure the strategy in your user resource:

      authentication do
        strategies do
          bank_id do
            order_resource MyApp.Accounts.BankIDOrder
            personal_number_field :personal_number
            given_name_field :given_name
            surname_field :surname
            verified_at_field :bankid_verified_at
            ip_address_field :ip_address
            order_ttl 180
            poll_interval 2000
          end
        end
      end

  ## User Resource Requirements

  Your user resource must have:

  - An identity on the configured `identity_field` (default: `:personal_number`)
  - Tokens enabled
  - The required attribute fields configured above

  ## Order Resource

  You must create an order resource to track BankID authentication sessions.
  See `AshAuthentication.BankID.OrderResource` for details.

  ## Security

  - QR start secrets are never sent to the client
  - Orders are bound to Phoenix sessions
  - Orders expire after the configured TTL (default: 3 minutes)
  - Orders are single-use (marked as consumed after completion)
  """

  alias __MODULE__.{Dsl, Transformer, Verifier}

  defstruct [
    :name,
    :resource,
    :order_resource,
    :identity_field,
    :personal_number_field,
    :given_name_field,
    :surname_field,
    :verified_at_field,
    :ip_address_field,
    :sign_in_action_name,
    :order_ttl,
    :poll_interval,
    :cleanup_interval,
    :consumed_order_ttl,
    :__spark_metadata__
  ]

  use AshAuthentication.Strategy.Custom, entity: Dsl.dsl()

  @type t :: %__MODULE__{
          name: atom,
          resource: module,
          order_resource: module,
          identity_field: atom,
          personal_number_field: atom,
          given_name_field: atom,
          surname_field: atom,
          verified_at_field: atom,
          ip_address_field: atom,
          sign_in_action_name: atom,
          order_ttl: pos_integer,
          poll_interval: pos_integer,
          cleanup_interval: pos_integer,
          consumed_order_ttl: pos_integer,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  # Delegate to transformer and verifier (required by Custom strategy pattern)
  defdelegate transform(strategy, dsl_state), to: Transformer
  defdelegate verify(strategy, dsl_state), to: Verifier
end
