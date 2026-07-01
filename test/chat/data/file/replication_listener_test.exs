defmodule Chat.Data.File.ReplicationListenerTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.Data.File.ReplicationListener

  defmodule FileDataMock do
    def insert_missing_chunks_placeholders(file_id, chunk_count, _peer_url, _now, _opts) do
      send(:repl_test, {:placeholders_inserted, file_id, chunk_count})
      :ok
    end

    def fill_missing_chunk(file_id, chunk_index, data_hash, size, _opts) do
      send(:repl_test, {:chunk_filled, file_id, chunk_index, data_hash, size})
      :ok
    end
  end

  defmodule DriveCopyMock do
    def chunk_fetchable(drive_id, file_id, chunk_index, source_drive_id) do
      send(:repl_test, {:chunk_fetchable_cast, drive_id, file_id, chunk_index, source_drive_id})
      :ok
    end
  end

  defmodule TimeKeeperMock do
    def now_unix, do: 1_000_000
  end

  rewire(ReplicationListener, [
    {Chat.Data.File, FileDataMock},
    {Chat.Data.File.DriveCopySource, DriveCopyMock},
    {Chat.TimeKeeper, TimeKeeperMock}
  ])

  @drive_id "test_repl_drive"

  setup do
    Process.register(self(), :repl_test)

    pid = start_listener()

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
    end)

    %{pid: pid}
  end

  describe "file_replicated notification" do
    test "inserts missing_chunks placeholders", %{pid: pid} do
      payload = Jason.encode!(%{"file_id" => "f_abc123", "chunk_count" => 5})

      send(pid, {:notification, nil, nil, "file_replicated", payload})
      wait_for_cast(pid)

      assert_received {:placeholders_inserted, "f_abc123", 5}
    end

    test "malformed payload does not crash", %{pid: pid} do
      send(pid, {:notification, nil, nil, "file_replicated", "not json"})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end

    test "missing fields in payload does not crash", %{pid: pid} do
      payload = Jason.encode!(%{"file_id" => "f_abc123"})

      send(pid, {:notification, nil, nil, "file_replicated", payload})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  describe "file_chunk_replicated notification" do
    test "fills hash/size and casts to DriveCopySource", %{pid: pid} do
      payload =
        Jason.encode!(%{
          "file_id" => "f_abc123",
          "chunk_index" => 2,
          "data_hash" => "fd_deadbeef",
          "size" => 4096
        })

      send(pid, {:notification, nil, nil, "file_chunk_replicated", payload})
      wait_for_cast(pid)

      assert_received {:chunk_filled, "f_abc123", 2, "fd_deadbeef", 4096}
      assert_received {:chunk_fetchable_cast, @drive_id, "f_abc123", 2, @drive_id}
    end

    test "malformed payload does not crash", %{pid: pid} do
      send(pid, {:notification, nil, nil, "file_chunk_replicated", "{bad"})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  describe "init" do
    test "starts with nil conn when no repo provided", %{pid: pid} do
      state = :sys.get_state(pid)

      assert state.conn == nil
      assert state.drive_id == @drive_id
    end
  end

  # Helpers

  defp start_listener do
    {:ok, pid} = GenServer.start_link(ReplicationListener, drive_id: @drive_id, repo: nil)
    pid
  end

  defp wait_for_cast(pid) do
    _ = :sys.get_state(pid)
  end
end
