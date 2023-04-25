defmodule Chat.ChunkedFilesMultisecret do
  @moduledoc "Multisecret handler for chunks ciphering of large files (>~1GB)"

  alias Chat.Db

  @chunk_size Application.compile_env(:chat, :file_chunk_size)
  @hundred_chunks_size 100 * @chunk_size
  @secret_size 32

  def generate(file_key, file_size, initial_secret) do
    secrets_needed_amount = trunc(file_size / @hundred_chunks_size)

    secrets_needed =
      for amount <- 0..secrets_needed_amount,
          amount > 0,
          do: encrypt_secret(additional_secret(), initial_secret)

    if secrets_needed == [],
      do: :ok,
      else: Db.put({:file_secrets, file_key}, secrets_needed |> Enum.join(""))
  end

  def get_secret(_file_key, offset, initial_secret)
      when offset < @hundred_chunks_size,
      do: initial_secret

  def get_secret(file_key, offset, initial_secret) do
    secrets = Db.get({:file_secrets, file_key})
    secret_offset_start = (trunc(offset / @hundred_chunks_size) - 1) * @secret_size

    secrets
    |> slice_binary(secret_offset_start, @secret_size)
    |> decrypt_secret(initial_secret)
  end

  defp encrypt_secret(additional_secret, initial_secret) do
    additional_secret
    |> Enigma.cipher(initial_secret)
  end

  defp decrypt_secret(encrypted, initial_secret) do
    encrypted
    |> Enigma.decipher(initial_secret)
  end

  defp additional_secret, do: Enigma.generate_secret()

  defp slice_binary(bin, start, length), do: :binary.part(bin, {start, length})
end
