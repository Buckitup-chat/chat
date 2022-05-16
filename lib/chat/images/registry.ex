defmodule Chat.Images.Registry do
  @moduledoc "Images registry"

  alias Chat.Db

  def add(key, value), do: Db.put({:images, key}, value)
  def get(key), do: Db.get({:images, key})
  def delete(key), do: Db.delete({:images, key})
end
