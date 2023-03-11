defmodule Chat.Content.Files do
  @moduledoc "Context for File operations"

  alias Chat.Content.Storage
  alias Chat.Db

  def get({key, secret}), do: get(key, secret)
  def get(key, secret), do: Storage.get_ciphered(db_key(key), secret)

  def delete({key, _secret}), do: delete(key)
  def delete(key), do: Db.delete(db_key(key))

  def add([key, raw_secret, _, _, _, _] = data) do
    secret = Base.decode64!(raw_secret)

    if Storage.get(db_key(key)) do
      {key, secret}
    else
      {key, Storage.cipher_and_store(db_key(key), data, secret)}
    end
  end

  defp db_key(key), do: {:file, key}
end
