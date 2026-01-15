defmodule AshAuthentication.BankID.Dsl do
  @moduledoc """
  DSL entity definition for the BankID authentication strategy.

  This module defines the configuration options available when setting up
  BankID authentication in your user resource.
  """

  @doc """
  Returns the Spark DSL entity for configuring BankID authentication.

  ## Configuration Options

  - `:name` - Unique identifier for this strategy (required, defaults to `:bank_id`)
  - `:order_resource` - The Ash resource that stores BankID orders (required)
  - `:identity_field` - Primary identity field for user lookup (default: `:personal_number`)
  - `:personal_number_field` - Field to store Swedish personal number (default: `:personal_number`)
  - `:given_name_field` - Field to store given name from BankID (default: `:given_name`)
  - `:surname_field` - Field to store surname from BankID (default: `:surname`)
  - `:verified_at_field` - Field to store verification timestamp (default: `:bankid_verified_at`)
  - `:ip_address_field` - Field to store IP address (default: `:ip_address`)
  - `:sign_in_action_name` - Name of the sign-in action (auto-generated if not provided)
  - `:order_ttl` - Order expiration time in seconds (default: 180)
  - `:poll_interval` - Recommended poll interval in milliseconds (default: 2000)

  ## Example

      authentication do
        strategies do
          bank_id do
            order_resource MyApp.Accounts.BankIDOrder
            personal_number_field :personal_number
            given_name_field :given_name
            surname_field :surname
            verified_at_field :bankid_verified_at
            order_ttl 180
          end
        end
      end
  """
  @spec dsl :: AshAuthentication.Strategy.Custom.entity()
  def dsl do
    %Spark.Dsl.Entity{
      name: :bank_id,
      describe: "Strategy for authenticating using Swedish BankID",
      args: [{:optional, :name, :bank_id}],
      hide: [:name],
      target: AshAuthentication.BankID,
      schema: [
        name: [
          type: :atom,
          doc: "Uniquely identifies the strategy.",
          required: true
        ],
        order_resource: [
          type: :atom,
          doc: "The Ash resource module that stores BankID orders.",
          required: true
        ],
        identity_field: [
          type: :atom,
          doc:
            "The field used as the primary identity for user lookup (usually personal_number).",
          default: :personal_number
        ],
        personal_number_field: [
          type: :atom,
          doc: "The field to store the Swedish personal number (personnummer).",
          default: :personal_number
        ],
        given_name_field: [
          type: :atom,
          doc: "The field to store the given name from BankID.",
          default: :given_name
        ],
        surname_field: [
          type: :atom,
          doc: "The field to store the surname from BankID.",
          default: :surname
        ],
        verified_at_field: [
          type: :atom,
          doc: "The field to store the BankID verification timestamp.",
          default: :bankid_verified_at
        ],
        ip_address_field: [
          type: :atom,
          doc: "The field to store the IP address used during authentication.",
          default: :ip_address
        ],
        sign_in_action_name: [
          type: :atom,
          doc:
            "The name of the sign-in action. Defaults to `sign_in_with_<strategy_name>` if not provided."
        ],
        order_ttl: [
          type: :pos_integer,
          doc: "Total authentication window in seconds (renewed orders created every ~30s).",
          default: 300
        ],
        order_renewal_interval: [
          type: :pos_integer,
          doc: "Interval in seconds to create new BankID orders (must be < 30s).",
          default: 28
        ],
        max_renewals: [
          type: :pos_integer,
          doc: "Maximum number of order renewals before timing out.",
          default: 10
        ],
        poll_interval: [
          type: :pos_integer,
          doc: "Recommended polling interval for checking order status in milliseconds.",
          default: 2000
        ],
        cleanup_interval: [
          type: :pos_integer,
          doc: """
          Interval in milliseconds between order cleanup runs.
          The cleanup process deletes expired and consumed orders from the database.
          Default: 300000 (5 minutes)
          """,
          default: 300_000
        ],
        consumed_order_ttl: [
          type: :pos_integer,
          doc: """
          Time in seconds to retain consumed (completed) orders before deletion.
          This is for audit and debugging purposes.
          Default: 86400 (24 hours)
          """,
          default: 86_400
        ]
      ]
    }
  end
end
