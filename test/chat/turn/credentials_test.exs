defmodule Chat.Turn.CredentialsTest do
  use ExUnit.Case, async: false

  alias Chat.Turn.Credentials

  test "test vector matches spec" do
    secret = "buckitup-test-secret"
    username = "1791200000:6f1c2a9d4e8b7a3c0d5e9f1a2b3c4d5e"

    assert Credentials.hmac(secret, username) == "lpJ4fKChsz/b21/Y2LZCo1ST4gc="
  end

  test "issue returns {username, credential, ttl}" do
    {username, credential, ttl} = Credentials.issue()

    assert is_binary(username)
    assert is_binary(credential)
    assert is_integer(ttl)

    [expiry_str, tag] = String.split(username, ":", parts: 2)
    assert String.to_integer(expiry_str) > System.os_time(:second)
    assert String.length(tag) == 32
    assert tag =~ ~r/\A[0-9a-f]{32}\z/
  end

  test "tags are unique across calls" do
    {u1, _, _} = Credentials.issue()
    {u2, _, _} = Credentials.issue()

    [_, tag1] = String.split(u1, ":", parts: 2)
    [_, tag2] = String.split(u2, ":", parts: 2)

    refute tag1 == tag2
  end
end
