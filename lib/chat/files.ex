defmodule Chat.Files do
  @moduledoc "Context for File oprations"

  alias Chat.Db
  alias Chat.Utils

  def get({key, secret}), do: get(key, secret)

  def get(key, secret) do
    blob = get_blob(key)

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Db.delete({:file, key})
  end

  def add([key, raw_secret, _, _, _, _] = data) do
    blob = get_blob(key)
    secret = Base.decode64!(raw_secret)

    if blob do
      {key, secret}
    else
      {blob, _secret} = Utils.encrypt_blob(data, secret)
      Db.put({:file, key}, blob)
    end

    {key, secret}
  end

  defp get_blob(key) do
    Db.get({:file, key})
  end
end
