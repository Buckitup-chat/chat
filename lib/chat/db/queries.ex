defmodule Chat.Db.Queries do
  @moduledoc "DB functions to retrieve and store data"

  alias Chat.Db

  def list(db, range, transform) do
    db
    |> list(range)
    |> Map.new(transform)
  end

  def list(db, {min, max}) do
    db
    |> CubDB.select(min_key: min, max_key: max)
  end

  def select(db, {min, max}, amount) do
    db
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true
    )
    |> Stream.take(amount)
  end

  def values(db, {min, max}, amount) do
    db
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true
    )
    |> Stream.take(amount)
    |> Stream.map(fn {_, v} -> v end)
  end

  def get_max_one(db, min, max) do
    db
    |> CubDB.select(
      min_key: min,
      max_key: max,
      max_key_inclusive: false,
      reverse: true
    )
    |> Enum.take(1)
  end

  def get(db, key) do
    db
    |> CubDB.get(key)
  end

  def get_next(db, key, max_key, predicate) do
    db
    |> CubDB.select(min_key: key, min_key_inclusive: false, max_key: max_key)
    |> Stream.filter(predicate)
    |> Stream.take(1)
    |> Enum.map(fn {{_, _, index, _}, msg} -> {index, msg} end)
    |> Enum.at(0)
  end

  def get_prev(db, key, min_key, predicate) do
    db
    |> CubDB.select(min_key: min_key, max_key: key, max_key_inclusive: false, reverse: true)
    |> Stream.filter(predicate)
    |> Stream.take(1)
    |> Enum.map(fn {{_, _, index, _}, msg} -> {index, msg} end)
    |> Enum.at(0)
  end

  def put(db, key, value) do
    if Db.writable?() do
      db
      |> CubDB.put(key, value)
    end
  end

  def delete(db, key) do
    if Db.writable?() do
      db
      |> CubDB.delete(key)
    end
  end

  def bulk_delete(db, {min, max}) do
    if Db.writable?() do
      key_list =
        CubDB.select(db,
          min_key: min,
          max_key: max
        )
        |> Enum.map(fn {key, _value} -> key end)

      CubDB.delete_multi(db, key_list)
    end
  end
end
