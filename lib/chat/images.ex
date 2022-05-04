defmodule Chat.Images do
  @moduledoc "Context for Image oprations"

  alias Chat.Images.Registry
  alias Chat.Utils

  def get({key, secret}), do: get(key, secret)

  def get(key, secret) do
    blob = Registry.get(key)

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Registry.delete(key)
  end

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = Utils.encrypt_blob(data)
    Registry.add(key, blob)

    {key, secret}
  end
end
