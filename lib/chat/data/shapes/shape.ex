defmodule Chat.Data.Shapes.Shape do
  @moduledoc """
  Behaviour for Electric-synced shapes.

  Each shape module declares its schema, versioning, and the logic
  for both pipelines (peer sync and HTTP ingestion).

  ## Callbacks

      +------------------+
      | Identity         |
      |  shape_name/0    |
      |  schema_module/0 |
      |  versions_schema/0  (default: nil)
      +------------------+
               |
      +--------v---------+     Peer sync pipeline
      | sync_required_   |     (ShapeWriter)
      |   parents/2      |---> [{shape, key}]
      +------------------+
               |
      +--------v---------+
      | sync_validate_   |     (default: :ok)
      |   parent/2       |---> :ok | {:reject, reason}
      +------------------+
               |
      +--------v---------+
      | sync_derive_     |     (default: identity)
      |   fields/1       |---> struct with computed fields
      +------------------+
               |
      +--------v---------+
      | sync_persist/2   |---> {:ok, _} | {:error, _}
      +------------------+

      +------------------+     HTTP ingestion pipeline
      | ingest_configure_|     (ElectricController)
      |   writer/2       |---> Writer.allow(writer, schema, ...)
      +------------------+
  """

  @type operation :: :insert | :update
  @type parent_ref :: {shape_name :: atom(), key :: term()}

  @callback shape_name() :: atom()

  @callback schema_module() :: module()

  @callback versions_schema() :: module() | nil

  @callback sync_required_parents(operation(), struct()) :: [parent_ref()]

  @callback sync_validate_parent(parent_ref(), struct()) :: :ok | {:reject, atom()}

  @callback sync_derive_fields(struct()) :: struct()

  @callback sync_persist(operation(), struct()) :: {:ok, term()} | {:error, term()}

  @callback ingest_configure_writer(Phoenix.Sync.Writer.t(), map()) :: Phoenix.Sync.Writer.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Chat.Data.Shapes.Shape

      @impl true
      def versions_schema, do: nil

      @impl true
      def sync_validate_parent(_parent_ref, _value), do: :ok

      @impl true
      def sync_derive_fields(value), do: value

      defoverridable versions_schema: 0, sync_validate_parent: 2, sync_derive_fields: 1
    end
  end
end
