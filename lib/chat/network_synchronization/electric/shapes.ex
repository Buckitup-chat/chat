defmodule Chat.NetworkSynchronization.Electric.Shapes do
  @moduledoc "Centralized definition of Electric shapes and their schema modules"

  @shapes %{
    user_card: Chat.Data.Schemas.UserCard,
    user_storage: Chat.Data.Schemas.UserStorage
  }

  def all, do: Map.keys(@shapes)

  def schema_module(shape), do: Map.fetch!(@shapes, shape)

  def shapes_map, do: @shapes
end
