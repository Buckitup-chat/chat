defmodule Chat.Images do
  @moduledoc "Context for Image oprations"

  alias Chat.Db
  alias Chat.Utils

  def get({key, secret}), do: get(key, secret)

  def get(key, secret) do
    blob = Db.get({:image, key})

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def get_meta(key, secret) do
    blob = Db.get({:image_meta, key})

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Db.delete({:image, key})
    Db.delete({:image_meta, key})
  end

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = Utils.encrypt_blob(data)
    Db.put({:image, key}, blob)
    Db.put({:image_meta, key}, blob |> Enum.drop(2))

    {key, secret}
  end
end
