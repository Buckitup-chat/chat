defmodule Chat.Db.Scope.Utils do
  @moduledoc """
  Utils for db key scope
  """

  def db_keys_stream(snap, min, max) do
    snap
    |> db_stream(min, max)
    |> Stream.map(&just_keys/1)
  end

  def db_stream(snap, min, max) do
    CubDB.Snapshot.select(snap, min_key: min, max_key: max)
  end

  def union_set(list, set) do
    list
    |> MapSet.new()
    |> MapSet.union(set)
  end

  def just_keys({k, _v}), do: k
end
