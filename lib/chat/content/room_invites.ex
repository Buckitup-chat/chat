defmodule Chat.Content.RoomInvites do
  @moduledoc "Context for Room Invites oprations"

  alias Chat.Content.Storage
  alias Chat.Db

  def get({key, secret}), do: get(key, secret)
  def get(key, secret), do: Storage.get_ciphered(db_key(key), secret)

  def delete({key, _secret}), do: delete(key)
  def delete(key), do: Db.delete(db_key(key))

  def add(data) do
    key = UUID.uuid4()

    {key, Storage.cipher_and_store(db_key(key), data)}
  end

  def pack(data) do
    key = UUID.uuid4()

    {key, Storage.cipher_and_pack(db_key(key), data)}
  end

  defp db_key(key), do: {:room_invite, key}
end
