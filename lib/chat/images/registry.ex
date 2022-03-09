defmodule Chat.Images.Registry do
  @moduledoc "Images registry"

  alias Chat.Db

  def add(key, value), do: Db.db() |> CubDB.put({:images, key}, value)
  def get(key), do: Db.db() |> CubDB.get({:images, key})
end
