defprotocol Chat.Proto.Shortcode do
  @moduledoc """
  Protocol for extracting a short code from entities with user_hash.

  Skips the first byte (prefix) and takes the next 3 bytes, encoded as hex.
  Example: user_hash 0x01aabbccdddddddd... => shortcode "aabbcc"
  """

  @doc """
  Returns a 6-character hex string representing bytes 2-4 of the user_hash.
  """
  def short_code(entity)
end

defimpl Chat.Proto.Shortcode, for: Chat.Data.Schemas.UserCard do
  def short_code(%Chat.Data.Schemas.UserCard{user_hash: user_hash}) do
    short_code_from_hash(user_hash)
  end

  defp short_code_from_hash(<<_prefix::binary-size(1), code::binary-size(3), _rest::binary>>) do
    Base.encode16(code, case: :lower)
  end
end
