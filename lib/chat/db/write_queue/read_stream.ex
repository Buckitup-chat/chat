defmodule Chat.Db.WriteQueue.ReadStream do
  @moduledoc """
  List of keys to be read from db and yielded into queue
  """

  require Record

  Record.defrecord(:read_stream,
    db: nil,
    keys: [],
    awaiter: nil
  )

  def read_stream_empty?(read_stream(keys: list)), do: [] == list

  def read_stream_yield(read_stream(db: db, keys: list, awaiter: awaiter) = stream) do
    {data, new_list} = read_list(db, list)

    if new_list == [] and awaiter do
      send(awaiter, :done)
    end

    {data, read_stream(stream, keys: new_list)}
  end

  defp chunk_keys([], keys, _), do: {keys, []}
  defp chunk_keys(rest, keys, 0), do: {keys, rest}

  defp chunk_keys([{:file_chunk, _, _, _} = key | rest], keys, _), do: {[key | keys], rest}
  defp chunk_keys([key | rest], keys, amount), do: chunk_keys(rest, [key | keys], amount - 1)

  defp read_list(db, list) do
    {keys, new_list} = chunk_keys(list, [], 100)

    keys
    |> Enum.map(&{&1, CubDB.get(db, &1)})
    |> Enum.reject(fn {_, x} -> is_nil(x) end)
    |> then(&{&1, new_list})
  rescue
    # in case source DB is dead we finish with the stream
    _ -> {[], []}
  end
end
