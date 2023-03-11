defmodule Chat.Utils.StorageId do
  @moduledoc "Helper function for storing enrypted content"

  def from_json(encoded) do
    <<secret::binary-size(32), key::binary>> = Base.url_decode64!(encoded)

    {key, secret}
  end

  def from_json_to_key(encoded) do
    encoded
    |> from_json()
    |> elem(0)
  end

  def to_json({key, secret}) do
    (secret <> key)
    |> Base.url_encode64()
  end
end
