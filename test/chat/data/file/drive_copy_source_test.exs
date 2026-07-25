defmodule Chat.Data.File.DriveCopySourceTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.Data.File.DriveCopySource

  defmodule DbMock do
    def repo_ready?(_), do: false
    def repo, do: __MODULE__
  end

  defmodule FileDataMock do
    def fetchable_missing_chunks_for_copy(_, _, _), do: []
    def missing_chunks_for_drive(_, _), do: []
    def delete_missing_chunk(_, _, _), do: :ok
    def increment_missing_chunk_attempts(_, _, _, _), do: :ok
    def get_missing_chunk_hash(_, _, _), do: "fd_" <> String.duplicate("ab", 64)
  end

  defmodule WriterMock do
    def submit(_, _, _, _), do: :ok
  end

  defmodule ChunkStoreMock do
    def fetch(_file_id, _chunk_index, _base_dir), do: {:ok, "mock_body"}
  end

  rewire(DriveCopySource, [
    {Chat.Db, DbMock},
    {Chat.Data.File, FileDataMock},
    {Chat.Data.File.ChunkWriter, WriterMock},
    {Chat.Data.File.ChunkStore, ChunkStoreMock}
  ])

  @drive_id "test_drive_#{System.unique_integer([:positive])}"

  setup do
    unless Process.whereis(Chat.TaskSupervisor),
      do: start_supervised!({Task.Supervisor, name: Chat.TaskSupervisor})

    pid = start_source(@drive_id)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
    end)

    %{pid: pid}
  end

  describe "drive mount/unmount" do
    test "drive_unmounted removes drive and cancels sweep timer", %{pid: pid} do
      inject_drive(pid, "sys_id_1", "/mnt/usb1")

      GenServer.cast(pid, {:drive_unmounted, "sys_id_1"})
      wait_for_cast(pid)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.other_drives, "sys_id_1")
      refute Map.has_key?(state.sweep_timers, "sys_id_1")
    end

    test "unmount before sweep timer fires prevents sweep", %{pid: pid} do
      inject_drive(pid, "sys_flap", "/mnt/usb_flap")

      GenServer.cast(pid, {:drive_unmounted, "sys_flap"})
      wait_for_cast(pid)

      Process.sleep(100)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.other_drives, "sys_flap")
      refute Map.has_key?(state.sweep_timers, "sys_flap")
    end
  end

  describe "PubSub integration" do
    test "responds to chunk_pipeline drive_unmounted broadcast", %{pid: pid} do
      inject_drive(pid, "sys_id_2", "/mnt/usb2")

      Phoenix.PubSub.broadcast(
        Chat.PubSub,
        "chunk_pipeline",
        {:chunk_pipeline, {:drive_unmounted, "sys_id_2"}}
      )

      wait_for_cast(pid)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.other_drives, "sys_id_2")
    end
  end

  describe "poll" do
    test "poll skipped when no other drives mounted", %{pid: pid} do
      send(pid, :poll)
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  describe "resolve_source_dir" do
    test "no drives mounted does not crash on chunk_fetchable", %{pid: pid} do
      GenServer.cast(pid, {:chunk_fetchable, "f_abc123", 0, "missing_drive"})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end

    test "falls back to random drive when source drive not mounted", %{pid: pid} do
      inject_drive(pid, "sys_id_1", "/mnt/usb1")

      GenServer.cast(pid, {:chunk_fetchable, "f_abc123", 0, "sys_gone"})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  # Helpers

  defp start_source(drive_id) do
    {:ok, pid} = GenServer.start_link(DriveCopySource, drive_id: drive_id, repo: nil)
    pid
  end

  defp inject_drive(pid, system_id, base_dir) do
    :sys.replace_state(pid, fn state ->
      others = Map.put(state.other_drives, system_id, base_dir)

      timers =
        Map.put(
          state.sweep_timers,
          system_id,
          Process.send_after(pid, {:sweep, system_id}, 5_000)
        )

      %{state | other_drives: others, sweep_timers: timers}
    end)
  end

  defp wait_for_cast(pid) do
    _ = :sys.get_state(pid)
  end
end
