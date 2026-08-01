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
               |
      +--------v---------+
      | sync_after_      |     (default: :ok)
      |   persist/3      |---> opts include peer_url when from peer sync
      +------------------+

      +------------------+     HTTP ingestion pipeline
      | ingest_configure_|     (ElectricController)
      |   writer/2       |---> Writer.allow(writer, schema, ...)
      +------------------+

  ## Persist helpers

  Pass `persist:` to `use Shape` to generate the standard
  persist_insert/persist_update/apply_changeset triad:

      use Chat.Data.Shapes.Shape,
        persist: [
          upsert: &ReviewData.upsert_review/1,
          get: &ReviewData.get_review/1,
          lookup_key: :review_hash,
          validate_insert: &Validation.validate_review_insert/1,
          validate_update: &Validation.validate_review_update/2
        ]
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

  @callback sync_after_persist(operation(), struct(), keyword()) :: :ok

  @callback ingest_configure_writer(Phoenix.Sync.Writer.t(), map()) :: Phoenix.Sync.Writer.t()

  defmacro __using__(opts) do
    persist_opts = Keyword.get(opts, :persist)

    persist_ast =
      if persist_opts do
        build_persist_helpers(persist_opts)
      else
        nil
      end

    quote do
      @behaviour Chat.Data.Shapes.Shape

      @impl true
      def versions_schema, do: nil

      @impl true
      def sync_validate_parent(_parent_ref, _value), do: :ok

      @impl true
      def sync_derive_fields(value), do: value

      @impl true
      def sync_after_persist(_operation, _struct, _opts), do: :ok

      @impl true
      def ingest_configure_writer(writer, _user_pop_context), do: writer

      defoverridable versions_schema: 0,
                     sync_validate_parent: 2,
                     sync_derive_fields: 1,
                     sync_after_persist: 3,
                     ingest_configure_writer: 2

      unquote(persist_ast)
    end
  end

  defp build_persist_helpers(opts) do
    upsert_fn = Keyword.fetch!(opts, :upsert)
    get_fn = Keyword.fetch!(opts, :get)
    lookup_key = Keyword.fetch!(opts, :lookup_key)
    validate_insert_fn = Keyword.fetch!(opts, :validate_insert)
    validate_update_fn = Keyword.fetch!(opts, :validate_update)

    lookup_call = build_lookup_call(get_fn, lookup_key)

    quote do
      @impl true
      def sync_persist(operation, record) do
        case operation do
          :insert ->
            changeset = unquote(validate_insert_fn).(record)
            persist_insert(changeset, record)

          :update ->
            persist_update(record)
        end
      end

      defp persist_insert(changeset, record) do
        case changeset do
          %{valid?: true} ->
            unquote(upsert_fn).(changeset)

          %{valid?: false} = cs ->
            log("Invalid #{shape_name()} insert: #{inspect(cs.errors)}", :warning)
            {:ok, record}
        end
      end

      defp persist_update(record) do
        case unquote(lookup_call) do
          nil ->
            {:ok, record}

          existing ->
            changeset = unquote(validate_update_fn).(existing, record)
            apply_changeset(changeset, record)
        end
      end

      defp apply_changeset(changeset, record) do
        schema = schema_module()

        case changeset do
          %{valid?: true} ->
            struct(schema)
            |> schema.create_changeset(Map.from_struct(record))
            |> unquote(upsert_fn).()

          %{valid?: false} = cs ->
            log("Invalid #{shape_name()} update: #{inspect(cs.errors)}", :warning)
            {:ok, record}
        end
      end
    end
  end

  defp build_lookup_call(get_fn, lookup_keys) when is_list(lookup_keys) do
    args = for key <- lookup_keys, do: quote(do: Map.get(record, unquote(key)))
    quote do: unquote(get_fn).(unquote_splicing(args))
  end

  defp build_lookup_call(get_fn, lookup_key) do
    quote do: unquote(get_fn).(Map.get(record, unquote(lookup_key)))
  end
end
