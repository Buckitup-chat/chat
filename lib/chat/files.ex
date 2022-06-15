defmodule Chat.Files do
  @moduledoc "Context for File oprations"

  alias Chat.Db
  alias Chat.Utils

  def get({key, secret}), do: get(key, secret)

  def get(key, secret) do
    blob = Db.get({:file, key})

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def get_meta(key, secret) do
    blob = Db.get({:file_meta, key})

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Db.delete({:file, key})
    Db.delete({:file_meta, key})
  end

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = Utils.encrypt_blob(data)
    Db.put({:file, key}, blob)
    Db.put({:file_meta, key}, blob |> Enum.drop(2))

    {key, secret}
  end
end
