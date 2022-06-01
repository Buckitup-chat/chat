defmodule Chat.RoomInvites do
  @moduledoc "Context for Room Invites oprations"

  alias Chat.Db
  alias Chat.Utils

  def get({key, secret}), do: get(key, secret)

  def get(key, secret) do
    blob = Db.get({:room_invite, key})

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Db.delete({:room_invite, key})
  end

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = Utils.encrypt_blob(data)
    Db.put({:room_invite, key}, blob)

    {key, secret}
  end
end
