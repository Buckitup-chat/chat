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

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Db.delete({:file, key})
  end

  def add([key, _, _, _, _, _] = data) do
    {blob, secret} = Utils.encrypt_blob(data)
    Db.put({:file, key}, blob)

    {key, secret}
  end
end
