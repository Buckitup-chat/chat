defprotocol Chat.Proto.Shortcode do
  @moduledoc """
  Protocol for extracting a short code from entities or hash strings.

  Preserves the prefix and takes the first 6 hex characters after it.
  Example: "u_aabbccdddddddd..." => "u_aabbcc"
  """

  @doc """
  Returns a shortened hash with prefix and 6 hex characters.
  """
  def short_code(entity)
end

defimpl Chat.Proto.Shortcode, for: Chat.Data.Schemas.UserCard do
  def short_code(%Chat.Data.Schemas.UserCard{user_hash: user_hash}) do
    Chat.Proto.Shortcode.short_code(user_hash)
  end
end

defimpl Chat.Proto.Shortcode, for: Atom do
  def short_code(nil), do: ""
end

defimpl Chat.Proto.Shortcode, for: BitString do
  def short_code(hash) when is_binary(hash) do
    case String.split(hash, "_", parts: 2) do
      [prefix, <<code::binary-size(6), _rest::binary>>] ->
        prefix <> "_" <> String.downcase(code)

      _ ->
        hash
    end
  end
end
