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
    test "drive_mounted registers drive and schedules sweep timer", %{pid: pid} do
      GenServer.cast(pid, {:drive_mounted, "usb1", "/mnt/usb1"})
      wait_for_cast(pid)

      state = :sys.get_state(pid)
      assert state.other_drives["usb1"] == "/mnt/usb1"
      assert is_reference(state.sweep_timers["usb1"])
    end

    test "drive_unmounted removes drive and cancels sweep timer", %{pid: pid} do
      GenServer.cast(pid, {:drive_mounted, "usb1", "/mnt/usb1"})
      wait_for_cast(pid)

      GenServer.cast(pid, {:drive_unmounted, "usb1"})
      wait_for_cast(pid)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.other_drives, "usb1")
      refute Map.has_key?(state.sweep_timers, "usb1")
    end

    test "self-mount is ignored", %{pid: pid} do
      GenServer.cast(pid, {:drive_mounted, @drive_id, "/mnt/self"})
      wait_for_cast(pid)

      state = :sys.get_state(pid)
      assert state.other_drives == %{}
    end

    test "unmount before sweep timer fires prevents sweep", %{pid: pid} do
      GenServer.cast(pid, {:drive_mounted, "usb_flap", "/mnt/usb_flap"})
      wait_for_cast(pid)

      GenServer.cast(pid, {:drive_unmounted, "usb_flap"})
      wait_for_cast(pid)

      Process.sleep(100)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.other_drives, "usb_flap")
      refute Map.has_key?(state.sweep_timers, "usb_flap")
    end
  end

  describe "PubSub integration" do
    test "responds to chunk_pipeline drive_mounted broadcast", %{pid: pid} do
      Phoenix.PubSub.broadcast(
        Chat.PubSub,
        "chunk_pipeline",
        {:chunk_pipeline, {:drive_mounted, "usb2", "/mnt/usb2"}}
      )

      wait_for_cast(pid)

      state = :sys.get_state(pid)
      assert state.other_drives["usb2"] == "/mnt/usb2"
    end

    test "responds to chunk_pipeline drive_unmounted broadcast", %{pid: pid} do
      GenServer.cast(pid, {:drive_mounted, "usb2", "/mnt/usb2"})
      wait_for_cast(pid)

      Phoenix.PubSub.broadcast(
        Chat.PubSub,
        "chunk_pipeline",
        {:chunk_pipeline, {:drive_unmounted, "usb2"}}
      )

      wait_for_cast(pid)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.other_drives, "usb2")
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
      GenServer.cast(pid, {:drive_mounted, "usb1", "/mnt/usb1"})
      wait_for_cast(pid)

      GenServer.cast(pid, {:chunk_fetchable, "f_abc123", 0, "usb_gone"})
      wait_for_cast(pid)

      assert Process.alive?(pid)
    end
  end

  # Helpers

  defp start_source(drive_id) do
    {:ok, pid} = GenServer.start_link(DriveCopySource, drive_id: drive_id, repo: nil)
    pid
  end

  defp wait_for_cast(pid) do
    _ = :sys.get_state(pid)
  end
end
