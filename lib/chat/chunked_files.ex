defmodule Chat.ChunkedFiles do
  @moduledoc "Chunked files logic"

  alias Chat.ChunkedFilesBroker
  alias Chat.Db
  alias Chat.Utils

  @spec new_upload() :: {key :: String.t(), secret :: String.t()}
  def new_upload do
    ChunkedFilesBroker.generate()
  end

  def save_upload_chunk(key, {chunk_start, chunk_end}, chunk) do
    secret = ChunkedFilesBroker.get(key)
    encoded = Utils.encrypt_blob(chunk, secret)

    Db.put({:file_chunk, key, chunk_start, chunk_end}, encoded)
  end

  def complete_upload?(key, filesize) do
    Db.list({
      {:file_chunk, key, 0, 0},
      {:file_chunk, key, nil, nil}
    })
    |> Enum.map_join(&elem(&1, 1))
    |> byte_size()
    |> then(&(&1 == filesize))
    |> tap(fn
      true -> ChunkedFilesBroker.forget(key)
      x -> x
    end)
  end

  def mark_consumed(key) do
    ChunkedFilesBroker.forget(key)
  end

  def delete(key) do
    Db.bulk_delete({
      {:file_chunk, key, 0, 0},
      {:file_chunk, key, nil, nil}
    })

    ChunkedFilesBroker.forget(key)
  end

  def read({key, secret}) do
    Db.list({
      {:file_chunk, key, 0, 0},
      {:file_chunk, key, nil, nil}
    })
    |> Enum.map(&elem(&1, 1))
    |> Utils.decrypt_blob(secret)
    |> Enum.join("")
  end
end
