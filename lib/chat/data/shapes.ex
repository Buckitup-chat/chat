defmodule Chat.Data.Shapes do
  @moduledoc "Registry of Replication and Electric synced shape behaviour modules"

  # order matters
  @shapes [
    Chat.Data.Shapes.UserCard,
    Chat.Data.Shapes.UserStorage,
    Chat.Data.Shapes.DialogKeys,
    Chat.Data.Shapes.DialogMessages,
    Chat.Data.Shapes.DialogMessageReactions,
    Chat.Data.Shapes.DialogMessageReceipts,
    Chat.Data.Shapes.File,
    Chat.Data.Shapes.FileChunk,
    Chat.Data.Shapes.Origin,
    Chat.Data.Shapes.Review,
    Chat.Data.Shapes.ReviewPublicPasswords,
    Chat.Data.Shapes.ReviewPostRight,
    Chat.Data.Shapes.ReviewRevokeRight,
    Chat.Data.Shapes.ReviewPasswordCandidate,
    Chat.Data.Shapes.ReviewPostRightCandidate,
    Chat.Data.Shapes.ReviewRevokeRightCandidate,
    Chat.Data.Shapes.ReviewList
  ]

  @not_syncable [
    Chat.Data.Shapes.ReviewPasswordCandidate,
    Chat.Data.Shapes.ReviewPostRightCandidate,
    Chat.Data.Shapes.ReviewRevokeRightCandidate
  ]

  @syncable @shapes -- @not_syncable

  def all, do: @shapes

  def by_name(name), do: Enum.find(@shapes, &(&1.shape_name() == name))

  def by_schema(mod), do: Enum.find(@shapes, &(&1.schema_module() == mod))

  def shape_names, do: Enum.map(@shapes, & &1.shape_name())

  def sync_shape_names, do: Enum.map(@syncable, & &1.shape_name())

  def sync_schemas do
    @syncable
    |> Enum.flat_map(fn shape ->
      [shape.schema_module() | List.wrap(shape.versions_schema())]
    end)
  end

  def primary_key(schema_module) do
    schema_module.__schema__(:primary_key)
  end

  def sync_tables do
    sync_schemas()
    |> Enum.map(& &1.__schema__(:source))
  end
end
