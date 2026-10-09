defmodule Chat.Pq.ReadSessionTest do
  use ExUnit.Case, async: true

  alias Chat.Pq.ReadSession

  test "issued token resolves to its user and shape" do
    token = ReadSession.issue("u_abc", :dialog_messages)

    assert {:ok, %{user_hash: "u_abc", shape: :dialog_messages}} = ReadSession.lookup(token)
  end

  test "tokens are distinct url-safe strings" do
    a = ReadSession.issue("u_abc", :file)
    b = ReadSession.issue("u_abc", :file)

    assert a != b
    assert a =~ ~r/^[A-Za-z0-9_-]{43}$/
  end

  test "unknown, nil and expired tokens are rejected" do
    expired = insert_expired_session()

    assert :error = ReadSession.lookup("nope")
    assert :error = ReadSession.lookup(nil)
    assert :error = ReadSession.lookup(expired)
  end

  test "cleanup sweeps expired sessions" do
    expired = insert_expired_session()
    live = ReadSession.issue("u_abc", :file)

    send(ReadSession, :cleanup)
    :sys.get_state(ReadSession)

    assert [] = :ets.lookup(ReadSession, expired)
    assert {:ok, _} = ReadSession.lookup(live)
  end

  defp insert_expired_session do
    token = "expired-#{System.unique_integer()}"
    past = System.monotonic_time(:millisecond) - 1
    :ets.insert(ReadSession, {token, "u_abc", :file, past})
    token
  end
end
