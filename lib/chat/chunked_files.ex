defmodule Chat.ChunkedFiles do
  @moduledoc "Chunked files logic"

  alias Chat.ChunkedFilesBroker
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db
  alias Chat.FileFs
  alias Chat.Identity

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

  def save_upload_chunk(key, {chunk_start, chunk_end}, _size, chunk) do
    with initial_secret <- ChunkedFilesBroker.get(key),
         {_, false} <- {:empty_initial_secret, is_nil(initial_secret)},
         secret <- ChunkedFilesMultisecret.get_secret(key, chunk_start, initial_secret),
         encoded <- Enigma.cipher(chunk, secret),
         chunk_full_key <- {:file_chunk, key, chunk_start, chunk_end} do
      Db.put_chunk({chunk_full_key, encoded})
      |> await_on_fs_or_retry(chunk_full_key, encoded)
      |> tap(fn
        :ok -> Db.put({:chunk_key, chunk_full_key}, true)
        x -> x
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

  @chunk_size Application.compile_env(:chat, :file_chunk_size)

  def stream_chunks(key, initial_secret) do
    FileFs.stream_file_chunks(key)
    |> Stream.with_index()
    |> Stream.map(fn {chunk, index} ->
      chunk_start = index * @chunk_size
      secret = get_secret_from_multisecret(key, chunk_start, initial_secret)
      Enigma.decipher(chunk, secret)
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
      |> Enigma.decipher(secret)
      |> :binary.part(start_bypass, range_length)

    {{first, first + range_length - 1}, data}
  end

  def encrypt_secret(secret, %Identity{private_key: private, public_key: public} = _me) do
    my_secret = Enigma.compute_secret(private, public)

    Enigma.cipher(secret, my_secret)
  end

  def decrypt_secret(encrypted_secret, %Identity{private_key: private, public_key: public} = _me) do
    my_secret = Enigma.compute_secret(private, public)

    Enigma.decipher(encrypted_secret, my_secret)
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

  defp await_on_fs_or_retry(:ok, chunk_full_key, encoded) do
    cond do
      check_file(chunk_full_key) -> :ok
      wait_and_check_file(1, chunk_full_key) -> :ok
      wait_and_check_file(2, chunk_full_key) -> :ok
      wait_and_check_file(7, chunk_full_key) -> :ok
      wait_and_check_file(23, chunk_full_key) -> :ok
      wait_and_check_file(61, chunk_full_key) -> :ok
      wait_and_check_file(117, chunk_full_key) -> :ok
      true -> retry_save_file(chunk_full_key, encoded)
    end
  end

  defp retry_save_file(chunk_full_key, encoded) do
    res = Db.put_chunk({chunk_full_key, encoded})

    cond do
      res != :ok -> res
      check_file(chunk_full_key) -> :ok
      wait_and_check_file(2, chunk_full_key) -> :ok
      wait_and_check_file(7, chunk_full_key) -> :ok
      wait_and_check_file(23, chunk_full_key) -> :ok
      wait_and_check_file(61, chunk_full_key) -> :ok
      true -> :failed_to_check_file
    end
  end

  defp wait_and_check_file(seconds, chunk_full_key) do
    seconds
    |> :timer.seconds()
    |> Process.sleep()

    check_file(chunk_full_key)
  end

  defp check_file({:file_chunk, file_key, chunk_start, chunk_end}) do
    FileFs.has_file?({file_key, chunk_start, chunk_end})
  end
end
