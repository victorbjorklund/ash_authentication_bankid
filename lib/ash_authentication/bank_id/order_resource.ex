defmodule AshAuthentication.BankID.OrderResource do
  @moduledoc """
  Ash Resource extension for BankID order tracking.

  This extension adds all necessary attributes and actions to a resource
  for tracking BankID authentication orders.

  ## Usage

  Add this extension to your order resource:

      defmodule MyApp.Accounts.BankIDOrder do
        use Ash.Resource,
          domain: MyApp.Accounts,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshAuthentication.BankID.OrderResource]

        postgres do
          table "bankid_orders"
          repo MyApp.Repo
        end
      end

  This will automatically add:
  - All required attributes (order_ref, qr tokens, session info, etc.)
  - CRUD actions (create, read, update, destroy)
  - Identity on order_ref
  - Timestamps

  ## Attributes Added

  - `id` - UUID primary key
  - `order_ref` - String (unique, BankID order reference)
  - `qr_start_token` - String (public QR token)
  - `qr_start_secret` - String (QR secret, sensitive)
  - `auto_start_token` - String (same-device token)
  - `start_t` - Integer (Unix timestamp)
  - `session_id` - String (Phoenix session binding)
  - `ip_address` - String (user IP)
  - `status` - String (pending/complete/failed)
  - `hint_code` - String (BankID hint code, nullable)
  - `completion_data` - Map (BankID completion data, nullable)
  - `consumed` - Boolean (prevents reuse)
  - `inserted_at` - DateTime
  - `updated_at` - DateTime

  ## Migration

  After adding this extension, generate a migration:

      mix ash.codegen create_bankid_orders
  """

  use Spark.Dsl.Extension,
    sections: [],
    transformers: [AshAuthentication.BankID.OrderResource.Transformer]
end

defmodule AshAuthentication.BankID.OrderResource.Transformer do
  @moduledoc false

  use Spark.Dsl.Transformer
  alias Ash.Resource
  alias Spark.Dsl.Transformer

  @doc false
  @impl true
  @spec before?(module) :: boolean
  def before?(Resource.Transformers.CachePrimaryKey), do: true
  def before?(Resource.Transformers.DefaultAccept), do: true
  def before?(Resource.Transformers.ValidateActionTypesSupported), do: true
  def before?(_), do: false

  @doc false
  @impl true
  @spec after?(module) :: boolean
  def after?(_), do: false

  @doc false
  @impl true
  def transform(dsl_state) do
    dsl_state
    |> add_attributes()
    |> add_identities()
    |> add_actions()
    |> then(&{:ok, &1})
  end

  defp add_attributes(dsl_state) do
    dsl_state
    |> Transformer.add_entity([:attributes], build_uuid_primary_key())
    |> Transformer.add_entity([:attributes], build_order_ref())
    |> Transformer.add_entity([:attributes], build_qr_start_token())
    |> Transformer.add_entity([:attributes], build_qr_start_secret())
    |> Transformer.add_entity([:attributes], build_auto_start_token())
    |> Transformer.add_entity([:attributes], build_start_t())
    |> Transformer.add_entity([:attributes], build_session_id())
    |> Transformer.add_entity([:attributes], build_ip_address())
    |> Transformer.add_entity([:attributes], build_status())
    |> Transformer.add_entity([:attributes], build_hint_code())
    |> Transformer.add_entity([:attributes], build_completion_data())
    |> Transformer.add_entity([:attributes], build_consumed())
    |> Transformer.add_entity([:attributes], build_inserted_at())
    |> Transformer.add_entity([:attributes], build_updated_at())
  end

  defp add_identities(dsl_state) do
    Transformer.add_entity(dsl_state, [:identities], build_unique_order_ref())
  end

  defp add_actions(dsl_state) do
    dsl_state
    |> Transformer.add_entity([:actions], build_create_action())
    |> Transformer.add_entity([:actions], build_read_action())
    |> Transformer.add_entity([:actions], build_update_action())
    |> Transformer.add_entity([:actions], build_destroy_action())
  end

  # Attribute builders

  defp build_uuid_primary_key do
    # Build as a regular attribute with primary key options
    # (uuid_primary_key entity has special handling that doesn't work well with transformers)
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :id,
      type: :uuid,
      primary_key?: true,
      allow_nil?: false,
      writable?: false,
      public?: true,
      default: &Ash.UUID.generate/0
    )
  end

  defp build_order_ref do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :order_ref,
      type: :string,
      allow_nil?: false,
      public?: true
    )
  end

  defp build_qr_start_token do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :qr_start_token,
      type: :string,
      allow_nil?: false,
      public?: true
    )
  end

  defp build_qr_start_secret do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :qr_start_secret,
      type: :string,
      allow_nil?: false,
      sensitive?: true,
      public?: false
    )
  end

  defp build_auto_start_token do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :auto_start_token,
      type: :string,
      allow_nil?: false,
      public?: true
    )
  end

  defp build_start_t do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :start_t,
      type: :integer,
      allow_nil?: false,
      public?: true
    )
  end

  defp build_session_id do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :session_id,
      type: :string,
      allow_nil?: false,
      public?: false
    )
  end

  defp build_ip_address do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :ip_address,
      type: :string,
      allow_nil?: false,
      public?: true
    )
  end

  defp build_status do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :status,
      type: :string,
      allow_nil?: false,
      default: "pending",
      public?: true
    )
  end

  defp build_hint_code do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :hint_code,
      type: :string,
      allow_nil?: true,
      public?: true
    )
  end

  defp build_completion_data do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :completion_data,
      type: :map,
      allow_nil?: true,
      public?: true
    )
  end

  defp build_consumed do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :consumed,
      type: :boolean,
      allow_nil?: false,
      default: false,
      public?: true
    )
  end

  defp build_inserted_at do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :inserted_at,
      type: :utc_datetime_usec,
      allow_nil?: false,
      public?: true,
      writable?: false,
      default: &DateTime.utc_now/0
    )
  end

  defp build_updated_at do
    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: :updated_at,
      type: :utc_datetime_usec,
      allow_nil?: false,
      public?: true,
      writable?: false,
      default: &DateTime.utc_now/0,
      update_default: &DateTime.utc_now/0
    )
  end

  # Identity builder

  defp build_unique_order_ref do
    Transformer.build_entity!(Ash.Resource.Dsl, [:identities], :identity,
      name: :unique_order_ref,
      keys: [:order_ref]
    )
  end

  # Action builders

  defp build_create_action do
    Transformer.build_entity!(Ash.Resource.Dsl, [:actions], :create,
      name: :create,
      primary?: true,
      arguments: [],
      accept: [
        :order_ref,
        :qr_start_token,
        :qr_start_secret,
        :auto_start_token,
        :start_t,
        :session_id,
        :ip_address,
        :status
      ]
    )
  end

  defp build_read_action do
    Transformer.build_entity!(Ash.Resource.Dsl, [:actions], :read,
      name: :read,
      primary?: true,
      arguments: []
    )
  end

  defp build_update_action do
    Transformer.build_entity!(Ash.Resource.Dsl, [:actions], :update,
      name: :update,
      primary?: true,
      arguments: [],
      accept: [:status, :hint_code, :completion_data, :consumed]
    )
  end

  defp build_destroy_action do
    Transformer.build_entity!(Ash.Resource.Dsl, [:actions], :destroy,
      name: :destroy,
      primary?: true,
      arguments: [],
      accept: []
    )
  end
end
