defmodule Chat.Data.Shapes do
  @moduledoc "Registry of Replication and Electric synced shape behaviour modules"

  @shapes [
    Chat.Data.Shapes.DialogKeys,
    Chat.Data.Shapes.DialogMessageReactions,
    Chat.Data.Shapes.DialogMessageReceipts,
    Chat.Data.Shapes.DialogMessages,
    Chat.Data.Shapes.File,
    Chat.Data.Shapes.FileChunk,
    Chat.Data.Shapes.UserCard,
    Chat.Data.Shapes.UserStorage
  ]

  def all, do: @shapes

  def by_name(name), do: Enum.find(@shapes, &(&1.shape_name() == name))

  def by_schema(mod), do: Enum.find(@shapes, &(&1.schema_module() == mod))

  def shape_names, do: Enum.map(@shapes, & &1.shape_name())

  def sync_schemas do
    @shapes
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
