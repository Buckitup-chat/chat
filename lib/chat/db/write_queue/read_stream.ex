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
  defp chunk_keys(list, keys, 0), do: {keys, list}

  defp chunk_keys([head | tail], keys, amount) do
    if match?({:file_chunk, _, _, _}, head) do
      {[head | keys], tail}
    else
      chunk_keys(tail, [head | keys], amount - 1)
    end
  end

  defp read_list(db, list) do
    {keys, new_list} = chunk_keys(list, [], 100)

    keys
    |> Enum.map(&{&1, CubDB.get(db, &1)})
    |> Enum.reject(fn {_, x} -> is_nil(x) end)
    |> then(&{&1, new_list})
  end
end
