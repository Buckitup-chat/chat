defmodule Chat.Turn.Credentials do
  @moduledoc "Issues short-lived TURN credentials (draft-uberti-rtcweb-turn-rest-00 §2.2)"

  alias Chat.Turn.Config

  @tag_bytes 16

  def issue do
    expiry = System.os_time(:second) + Config.ttl()
    tag = :crypto.strong_rand_bytes(@tag_bytes) |> Base.encode16(case: :lower)
    username = "#{expiry}:#{tag}"
    credential = hmac(Config.secret(), username)

    {username, credential, Config.ttl()}
  end

  def hmac(secret, username) do
    :crypto.mac(:hmac, :sha, secret, username)
    |> Base.encode64()
  end
end
