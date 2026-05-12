defmodule Chat.Data.Shapes do
  @moduledoc "Registry of Electric-synced shape behaviour modules"

  @shapes [
    Chat.Data.Shapes.File,
    Chat.Data.Shapes.FileChunk,
    Chat.Data.Shapes.UserCard,
    Chat.Data.Shapes.UserStorage
  ]

  def all, do: @shapes

  def by_name(name), do: Enum.find(@shapes, &(&1.shape_name() == name))

  def by_schema(mod), do: Enum.find(@shapes, &(&1.schema_module() == mod))

  def shape_names, do: Enum.map(@shapes, & &1.shape_name())
end
