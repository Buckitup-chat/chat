defmodule Chat.Turn.Auth do
  @moduledoc "TURN credential verification for the stun listener's auth_fun callback"

  alias Chat.Turn.AllocationTracker
  alias Chat.Turn.Config

  @doc """
  The credential for `username`, or `""` to refuse it. A credential holding
  `AllocationTracker.max_per_user/0` allocations comes back as expired: stun
  then refuses its new allocations but keeps refreshing the live ones.
  """
  @spec auth_fun(binary(), binary()) :: binary() | {:expired, binary()}
  def auth_fun(username, realm) when is_binary(username) and is_binary(realm) do
    with :ok <- check_realm(realm),
         {:ok, expiry_str, tag} <- parse_username(username),
         {:ok, expiry} <- parse_expiry(expiry_str),
         :ok <- check_not_expired(expiry) do
      username
      |> credential(tag)
      |> expire_at_limit(username)
    else
      _ -> <<"">>
    end
  end

  def auth_fun(_username, _realm), do: <<"">>

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

  defp expire_at_limit(credential, username) do
    if AllocationTracker.user_at_limit?(username), do: {:expired, credential}, else: credential
  end

  defp credential(username, _tag) do
    :crypto.mac(:hmac, :sha, Config.secret(), username)
    |> Base.encode64()
  end
end
