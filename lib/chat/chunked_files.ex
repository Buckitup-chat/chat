defmodule Chat.ChunkedFiles do
  @moduledoc "Chunked files logic"

  alias Chat.ChunkedFilesBroker
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db
  alias Chat.FileFs
  alias Chat.Identity
  alias Chat.Utils

  @type key :: String.t()
  @type secret :: String.t()

  @spec new_upload(key()) :: secret()
  def new_upload(key) do
    ChunkedFilesBroker.generate(key)
  end

  def get_file(key) do
    ChunkedFilesBroker.get(key)
  end

  def next_chunk(key) do
    Db.list({
      {:chunk_key, {:file_chunk, key, 0, 0}},
      {:chunk_key, {:file_chunk, key, nil, nil}}
    })
    |> Enum.count()
  end

  def save_upload_chunk(key, {chunk_start, chunk_end}, chunk) do
    with initial_secret <- ChunkedFilesBroker.get(key),
         false <- is_nil(initial_secret),
         secret <- ChunkedFilesMultisecret.get_secret(key, chunk_start, initial_secret),
         encoded <- Utils.encrypt_blob(chunk, secret) do
      Db.put_chunk({{:file_chunk, key, chunk_start, chunk_end}, encoded})
      |> tap(fn
        :ok -> Db.put({:chunk_key, {:file_chunk, key, chunk_start, chunk_end}}, true)
        _ -> :ignore
      end)
    end
  end

  def complete_upload?(key, filesize) do
    key
    |> FileFs.count_size_stored()
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
    FileFs.delete_file(key)

    Db.bulk_delete({
      {:chunk_key, {:file_chunk, key, 0, 0}},
      {:chunk_key, {:file_chunk, key, nil, nil}}
    })

    ChunkedFilesBroker.forget(key)
  end

  def read({key, secret}) do
    key
    |> stream_chunks(secret)
    |> Enum.join("")
  end

  @chunk_size 10 * 1024 * 1024

  def stream_chunks(key, initial_secret) do
    FileFs.stream_file_chunks(key)
    |> Stream.with_index()
    |> Stream.map(fn {chunk, index} ->
      chunk_start = index * @chunk_size
      secret = get_secret_from_multisecret(key, chunk_start, initial_secret)
      Utils.decrypt_blob(chunk, secret)
    end)
  end

  def size(key) do
    FileFs.file_size(key)
  rescue
    _ -> 0
  end

  def chunk_with_byterange({key, secret}),
    do: chunk_with_byterange({key, secret}, {0, @chunk_size - 1})

  def chunk_with_byterange({key, secret}, {first, nil}),
    do: chunk_with_byterange({key, secret}, {first, first + @chunk_size - 1})

  def chunk_with_byterange({key, initial_secret}, {first, last}) do
    chunk_n = div(first, @chunk_size)
    chunk_start = chunk_n * @chunk_size
    start_bypass = first - chunk_start

    secret = get_secret_from_multisecret(key, chunk_start, initial_secret)
    {encrypt_blob, chunk_end} = FileFs.read_file_chunk(chunk_start, key)

    range_length = min(last, chunk_end) - first + 1

    data =
      encrypt_blob
      |> Utils.decrypt_blob(secret)
      |> :binary.part(start_bypass, range_length)

    {{first, first + range_length - 1}, data}
  end

  def encrypt_secret(secret, %Identity{} = me) do
    secret
    |> Base.encode64()
    |> Utils.encrypt(me)
  end

  def decrypt_secret(encrypted_secret, %Identity{} = me) do
    encrypted_secret
    |> Utils.decrypt(me)
    |> Base.decode64!()
  end

  def file_chunk_ranges(size) do
    make_chunk_ranges(0, size - 1, @chunk_size, [])
  end

  defp make_chunk_ranges(start, max, _chunk_size, acc) when start > max, do: acc |> Enum.reverse()

  defp make_chunk_ranges(start, max, chunk_size, acc) do
    make_chunk_ranges(
      start + chunk_size,
      max,
      chunk_size,
      [{start, min(start + chunk_size - 1, max)} | acc]
    )
  end

  defp get_secret_from_multisecret(key, chunk_start, initial_secret) do
    ChunkedFilesMultisecret.get_secret(key, chunk_start, initial_secret)
  end
end
