defmodule Chat.Turn.Auth do
  @moduledoc "TURN credential verification for the stun listener's auth_fun callback"

  alias Chat.Turn.Config

  @spec auth_fun(binary(), binary()) :: binary()
  def auth_fun(username, realm) do
    with :ok <- check_realm(realm),
         {:ok, expiry_str, tag} <- parse_username(username),
         {:ok, expiry} <- parse_expiry(expiry_str),
         :ok <- check_not_expired(expiry) do
      credential(username, tag)
    else
      _ -> <<"">>
    end
  rescue
    _ -> <<"">>
  end

  defp check_realm(realm) do
    if realm == Config.realm(), do: :ok, else: :error
  end

  defp parse_username(username) do
    case String.split(username, ":", parts: 2) do
      [expiry_str, tag] when byte_size(tag) > 0 -> {:ok, expiry_str, tag}
      _ -> :error
    end
  end

  defp parse_expiry(expiry_str) do
    case Integer.parse(expiry_str) do
      {expiry, ""} -> {:ok, expiry}
      _ -> :error
    end
  end

  defp check_not_expired(expiry) do
    if expiry > System.os_time(:second), do: :ok, else: :error
  end

  defp credential(username, _tag) do
    :crypto.mac(:hmac, :sha, Config.secret(), username)
    |> Base.encode64()
  end
end
