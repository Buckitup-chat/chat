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

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = Utils.encrypt_blob(data)
    Db.put({:file, key}, blob)

    {key, secret}
  end
end
