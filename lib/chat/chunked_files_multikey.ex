defmodule Chat.ChunkedFilesMultikey do
  @moduledoc false

  alias Chat.Db
  alias Chat.Utils

  @chunk_group_size 1000 * 1024 * 1024
  @secret_size 32

  def generate(file_key, file_size, <<initial_secret::binary-size(@secret_size)>>) do
    secrets_needed_amount = trunc(file_size / @chunk_group_size)

    secrets_needed =
      for amount <- 0..secrets_needed_amount,
          amount > 0,
          do: encrypt_secret(additional_secret(), initial_secret)

    if secrets_needed == [],
      do: :ok,
      else: Db.put({:file_secrets, file_key}, secrets_needed |> Enum.join(""))
  end

  def get_secret(_file_key, offset, <<initial_secret::binary-size(@secret_size)>>)
      when offset <= @chunk_group_size,
      do: initial_secret

  def get_secret(file_key, offset, <<initial_secret::binary-size(@secret_size)>>) do
    secrets = Db.get({:file_secrets, file_key})
    secret_offset_start = (trunc(offset / @chunk_group_size) - 1) * @secret_size

    secrets
    |> String.slice(secret_offset_start, @secret_size)
    |> decrypt_secret(initial_secret)
  end

  defp encrypt_secret(additional_secret, initial_secret) do
    additional_secret
    |> Utils.encrypt_blob(initial_secret)
  end

  defp decrypt_secret(encrypted, initial_secret) do
    encrypted
    |> Utils.decrypt_blob(initial_secret)
  end

  defp additional_secret, do: :crypto.strong_rand_bytes(@secret_size)
end
