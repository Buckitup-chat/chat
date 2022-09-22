defmodule Chat.FileDb do
  @moduledoc """
  Manages the state of the CubDB instance.
  """
  require Logger

  import Chat.Db.Common

  alias Chat.Db
  alias Chat.Db.Queries

  def list(range, transform), do: Queries.list(Db.file_db(), range, transform)
  def list({_min, _max} = range), do: Queries.list(Db.file_db(), range)
  def select({_min, _max} = range, amount), do: Queries.select(Db.file_db(), range, amount)
  def values({_min, _max} = range, amount), do: Queries.values(Db.file_db(), range, amount)
  def get_max_one(min, max), do: Queries.get_max_one(Db.file_db(), min, max)
  def get(key), do: Queries.get(Db.file_db(), key)

  def get_next(key, max_key, predicate),
    do: Queries.get_next(Db.file_db(), key, max_key, predicate)

  def get_prev(key, min_key, predicate),
    do: Queries.get_prev(Db.file_db(), key, min_key, predicate)

  def put(key, value),
    do: writable_action(fn -> budgeted_put(Db.file_db(), key, value) end)

  def delete(key),
    do: writable_action(fn -> Queries.delete(Db.file_db(), key) end)

  def bulk_delete({_min, _max} = range),
    do: writable_action(fn -> Queries.bulk_delete(Db.file_db(), range) end)
end
