defmodule Chat.Storage.Link.Filter do
  @moduledoc """
  Narrows a link's data flow consistently across its three layers.

  - `cub_scope` — CubDB keys to copy: `nil` (all) or a function of the link that
    returns the keys set for `Chat.Db.Copying.await_copied/3`.
  - `schemas` — PG schemas to diff-copy and publish; `nil` = `Chat.Data.Shapes.sync_schemas/0`.
  - `rows` — per-schema row predicate, `%{schema => query_fun}`. Defined, not applied yet.
  - `files` — `:referenced`: blobs only for chunk rows that made it through.

  Only `cub_scope` and `schemas` are applied for now (#805).

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.7.2.
  """

  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Shapes

  defstruct cub_scope: nil, schemas: nil, rows: %{}, files: :referenced

  @type t :: %__MODULE__{
          cub_scope: (Chat.Storage.Link.t() -> term()) | nil,
          schemas: [module()] | nil,
          rows: %{module() => (Ecto.Queryable.t() -> Ecto.Queryable.t())},
          files: :referenced
        }

  @doc "CubDB keys the link copies; `nil` for all."
  @spec cub_keys(:all | t(), Chat.Storage.Link.t()) :: term()
  def cub_keys(filter, link) do
    case filter do
      %__MODULE__{cub_scope: scope} when is_function(scope, 1) -> scope.(link)
      _ -> nil
    end
  end

  @doc "PG schemas the link syncs."
  @spec schemas(:all | t()) :: [module()]
  def schemas(filter) do
    case filter do
      %__MODULE__{schemas: [_ | _] = schemas} -> schemas
      _ -> Shapes.sync_schemas()
    end
  end

  @doc "PG tables the link publishes."
  @spec tables(:all | t()) :: [String.t()]
  def tables(filter), do: filter |> schemas() |> Enum.map(& &1.__schema__(:source))

  @doc "Whether chunk rows pass the filter, so their blobs are tracked."
  @spec chunks?(:all | t()) :: boolean()
  def chunks?(filter), do: FileChunk in schemas(filter)
end
