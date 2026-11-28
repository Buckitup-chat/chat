defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClient.Rows do
  @moduledoc "Decoding of shape row values (unpadded base64 bytea, stringified integers)."

  @doc "Decodes an unpadded base64 bytea value from a shape row."
  def decode_b64(value) when is_binary(value), do: Base.decode64!(value, padding: false)

  @doc "Integer from a shape row value, which may arrive as a string."
  def parse_int(v) when is_integer(v), do: v
  def parse_int(v) when is_binary(v), do: String.to_integer(v)
end
