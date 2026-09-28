defmodule Chat.NetworkSynchronization.Electric.ReadSessionsTest do
  use ExUnit.Case, async: true

  alias Chat.NetworkSynchronization.Electric.ReadSessions

  @peer "http://peer.local"
  @required {:ok, %{status: 401, body: %{"error" => "read_session_required", "shape" => "file"}}}

  setup ctx do
    name = :"read_sessions_#{System.unique_integer([:positive])}"
    start_supervised!({ReadSessions, name: name, opener: recording_opener(ctx)})
    %{rs: name}
  end

  test "no header until a session is opened", %{rs: rs} do
    assert [] = file_headers(rs)
    refute_opened()
  end

  test "passes through when not gated", %{rs: rs} do
    assert {:ok, %{status: 200}} = request_file(rs, fn [] -> {:ok, %{status: 200}} end)
    refute_opened()
  end

  test "opens on 401 read_session_required and retries with the bearer", %{rs: rs} do
    request = fn
      [] -> @required
      [{"authorization", "Bearer tok"}] -> {:ok, %{status: 200}}
    end

    assert {:ok, %{status: 200}} = request_file(rs, request)
    assert_received {:opened, @peer, :file}
    assert file_headers(rs) == bearer("tok")
    assert [] = ReadSessions.headers(@peer, :user_card, rs)
  end

  test "a second 401 is returned as is", %{rs: rs} do
    assert @required = request_file(rs, fn _ -> @required end)
  end

  @tag answer: {:error, :not_in_trust_chain}
  test "failed open surfaces as read_session error", %{rs: rs} do
    assert {:error, {:read_session, :not_in_trust_chain}} =
             request_file(rs, fn _ -> @required end)

    assert [] = file_headers(rs)
  end

  @tag open_delay: 100
  test "concurrent opens of one shape share a single request", %{rs: rs} do
    assert [:ok, :ok, :ok, :ok, :ok] = open_file_concurrently(rs, 5)
    assert_received {:opened, @peer, :file}
    refute_opened()
  end

  @tag answer: {:ok, "short", 30}
  test "renews a token with less than 60 s left", %{rs: rs} do
    assert :ok = ReadSessions.open(@peer, :file, rs)
    assert_received {:opened, @peer, :file}

    assert file_headers(rs) == bearer("short")
    assert_received {:opened, @peer, :file}
  end

  test "blocked_by/1 picks the read-session reason from a stream exit" do
    assert :unknown_user = ReadSessions.blocked_by(stream_exit({:read_session, :unknown_user}))
    assert nil == ReadSessions.blocked_by(stream_exit(nil))
    assert nil == ReadSessions.blocked_by(:normal)
  end

  # Helpers

  defp recording_opener(ctx) do
    test_pid = self()
    answer = Map.get(ctx, :answer, {:ok, "tok", 300})
    delay = Map.get(ctx, :open_delay, 0)

    fn peer_url, shape ->
      send(test_pid, {:opened, peer_url, shape})
      Process.sleep(delay)
      answer
    end
  end

  defp request_file(rs, request_fun), do: ReadSessions.request(@peer, :file, request_fun, rs)

  defp file_headers(rs), do: ReadSessions.headers(@peer, :file, rs)

  defp open_file_concurrently(rs, count) do
    1..count
    |> Enum.map(fn _ -> Task.async(fn -> ReadSessions.open(@peer, :file, rs) end) end)
    |> Task.await_many()
  end

  defp stream_exit(resp), do: {%Electric.Client.Error{message: "x", resp: resp}, []}

  defp bearer(token), do: [{"authorization", "Bearer " <> token}]

  defp refute_opened, do: refute_received({:opened, _, _})
end
