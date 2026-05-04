defprotocol Chat.Proto.Shortcode do
  @moduledoc """
  Protocol for extracting a short code from entities with user_hash.

  Takes first 6 hex characters after the "u_" prefix.
  Example: user_hash "u_aabbccdddddddd..." => shortcode "aabbcc"
  """

  @doc """
  Returns a 6-character hex string from the user_hash.
  """
  def short_code(entity)
end

defimpl Chat.Proto.Shortcode, for: Chat.Data.Schemas.UserCard do
  def short_code(%Chat.Data.Schemas.UserCard{user_hash: user_hash}) do
    short_code_from_hash(user_hash)
  end

  defp short_code_from_hash(<<"u_", code::binary-size(6), _rest::binary>>) do
    String.downcase(code)
  end
end
