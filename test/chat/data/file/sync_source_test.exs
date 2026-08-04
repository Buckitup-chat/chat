defmodule Chat.Data.File.SyncSourceTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.Data.File.SyncSource

  defmodule DbMock do
    def repo_ready?(_), do: false
    def repo, do: __MODULE__
  end

  defmodule FileDataMock do
    def fetchable_missing_chunks_for_sync(_, _, _), do: []
    def missing_chunks_for_peer(_, _), do: []
    def delete_missing_chunk(_, _, _), do: :ok
    def increment_missing_chunk_attempts(_, _, _, _), do: :ok
    def get_missing_chunk_hash(_, _, _), do: "fd_" <> String.duplicate("ab", 64)
  end

  defmodule WriterMock do
    def submit(_, _, _, _), do: :ok
    def lane_idle?(_, _), do: true
  end

  defmodule ReqMock do
    def get(url, _opts) do
      Agent.update(:ss_test_calls, &[url | &1])
      fail_prefix = Agent.get(:ss_test_fail_peer, & &1)

      if fail_prefix && String.starts_with?(url, fail_prefix) do
        {:error, :econnrefused}
      else
        {:ok, %{status: 200, body: "mock_body"}}
      end
    end
  end

  rewire(SyncSource, [
    {Chat.Db, DbMock},
    {Chat.Data.File, FileDataMock},
    {Chat.Data.File.ChunkWriter, WriterMock},
    {Req, ReqMock}
  ])

  @drive_id "test_sync_drive_#{System.unique_integer([:positive])}"

  setup do
    unless Process.whereis(Chat.TaskSupervisor),
      do: start_supervised!({Task.Supervisor, name: Chat.TaskSupervisor})

    start_supervised!(%{
      id: :ss_test_calls,
      start: {Agent, :start_link, [fn -> [] end, [name: :ss_test_calls]]}
    })

    start_supervised!(%{
      id: :ss_test_fail_peer,
      start: {Agent, :start_link, [fn -> nil end, [name: :ss_test_fail_peer]]}
    })

    pid = start_source(@drive_id)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
    end)

    %{pid: pid}
  end

  describe "peer connect/disconnect" do
    test "peer_connected registers peer and schedules sweep timer", %{pid: pid} do
      GenServer.cast(pid, {:peer_connected, "http://peer1:4444"})
      wait_for_cast(pid)

      state = :sys.get_state(pid)
      assert MapSet.member?(state.peers, "http://peer1:4444")
      assert is_reference(state.sweep_timers["http://peer1:4444"])
    end

    test "peer_disconnected removes peer and cancels sweep timer", %{pid: pid} do
      GenServer.cast(pid, {:peer_connected, "http://peer1:4444"})
      wait_for_cast(pid)

      GenServer.cast(pid, {:peer_disconnected, "http://peer1:4444"})
      wait_for_cast(pid)

      state = :sys.get_state(pid)
      refute MapSet.member?(state.peers, "http://peer1:4444")
      refute Map.has_key?(state.sweep_timers, "http://peer1:4444")
    end

    test "disconnect before sweep timer fires prevents sweep", %{pid: pid} do
      GenServer.cast(pid, {:peer_connected, "http://flappy:4444"})
      wait_for_cast(pid)

      GenServer.cast(pid, {:peer_disconnected, "http://flappy:4444"})
      wait_for_cast(pid)

      Process.sleep(100)

      state = :sys.get_state(pid)
      refute MapSet.member?(state.peers, "http://flappy:4444")
      refute Map.has_key?(state.sweep_timers, "http://flappy:4444")
    end

    test "disconnect without prior connect is a no-op", %{pid: pid} do
      GenServer.cast(pid, {:peer_disconnected, "http://unknown:4444"})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  describe "poll" do
    test "poll skipped when repo not ready", %{pid: pid} do
      send(pid, :poll)
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  describe "chunk_fetchable" do
    test "does not crash when no peers available", %{pid: pid} do
      GenServer.cast(pid, {:chunk_fetchable, "f_abc123", 0, "http://gone:4444"})
      wait_for_cast(pid)
      Process.sleep(200)

      assert Process.alive?(pid)
    end

    test "falls back to a different peer when the assigned peer's fetch fails", %{pid: pid} do
      GenServer.cast(pid, {:peer_connected, "http://primary:4444"})
      wait_for_cast(pid)
      GenServer.cast(pid, {:peer_connected, "http://fallback:4444"})
      wait_for_cast(pid)

      Agent.update(:ss_test_fail_peer, fn _ -> "http://primary:4444" end)

      GenServer.cast(pid, {:chunk_fetchable, "f_abc123", 0, "http://primary:4444"})
      wait_for_cast(pid)
      Process.sleep(200)

      urls = Agent.get(:ss_test_calls, &Enum.reverse(&1))

      assert Enum.any?(urls, &String.starts_with?(&1, "http://primary:4444"))
      assert Enum.any?(urls, &String.starts_with?(&1, "http://fallback:4444"))
    end
  end

  # Helpers

  defp start_source(drive_id) do
    {:ok, pid} = GenServer.start_link(SyncSource, drive_id: drive_id, repo: nil)
    pid
  end

  defp wait_for_cast(pid) do
    _ = :sys.get_state(pid)
  end
end
