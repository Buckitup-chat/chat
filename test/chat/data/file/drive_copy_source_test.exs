defmodule Chat.Data.File.DriveCopySourceTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.Data.File.ChunkStore
  alias Chat.Data.File.DriveCopySource
  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Storage.Unit
  alias Chat.Storage.Units

  @body "chunk body"
  @file_id "f_00000000000000000000000000000abc"

  defmodule DbMock do
    def repo_ready?(_), do: false
  end

  defmodule FileDataMock do
    def fetchable_missing_chunks_for_copy(_, _, _), do: []
    def missing_chunks_for_drive(_, _), do: []
    def delete_missing_chunk(_, _, _), do: :ok

    def increment_missing_chunk_attempts(file_id, chunk_index, _, _),
      do: send(:dcs_test, {:failed, file_id, chunk_index})

    def get_missing_chunk_hash(_, _, _),
      do: "chunk body" |> EnigmaPq.hash() |> FileChunkDataHash.from_binary()
  end

  defmodule WriterMock do
    def submit(drive_id, lane, body, meta) do
      send(:dcs_test, {:submitted, drive_id, lane, body, meta})
      :ok
    end
  end

  rewire(DriveCopySource, [
    {Chat.Db, DbMock},
    {Chat.Data.File, FileDataMock},
    {Chat.Data.File.ChunkWriter, WriterMock}
  ])

  # Stands in for the internal unit; the real one is up in the test env under id :internal
  @own %Unit{id: "sdo1", role: :internal, root: "/nonexistent"}

  setup do
    Process.register(self(), :dcs_test)

    tmp_dir = System.tmp_dir!() |> Path.join("dcs_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, pid} = GenServer.start_link(DriveCopySource, unit: @own)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000) end)

    %{pid: pid, tmp_dir: tmp_dir}
  end

  describe "fetch from other units" do
    test "fetches a chunk from a registered backup unit", %{pid: pid, tmp_dir: tmp_dir} do
      backup = register(%Unit{id: "sdb1", role: :backup, root: tmp_dir, system_id: "sys_b"})
      :ok = ChunkStore.put(backup, @file_id, 0, @body)

      GenServer.cast(pid, {:chunk_fetchable, @file_id, 0, "sys_b"})

      assert_receive {:submitted, "sdo1", :drive_copy, @body,
                      %{file_id: @file_id, chunk_index: 0}}
    end

    test "falls back to the other units when the source unit is gone", %{pid: pid, tmp_dir: tmp} do
      backup = register(%Unit{id: "sdb1", role: :backup, root: tmp, system_id: "sys_b"})
      :ok = ChunkStore.put(backup, @file_id, 0, @body)

      GenServer.cast(pid, {:chunk_fetchable, @file_id, 0, "sys_gone"})

      assert_receive {:submitted, "sdo1", :drive_copy, @body, _meta}
    end

    test "falls back to the next unit when the source unit lacks the chunk", %{pid: pid} = ctx do
      register(%Unit{id: "sdb1", role: :backup, root: ctx.tmp_dir <> "/b", system_id: "sys_b"})

      main =
        register(%Unit{id: "sdm1", role: :main, root: ctx.tmp_dir <> "/m", system_id: "sys_m"})

      :ok = ChunkStore.put(main, @file_id, 0, @body)

      GenServer.cast(pid, {:chunk_fetchable, @file_id, 0, "sys_b"})

      assert_receive {:submitted, "sdo1", :drive_copy, @body, _meta}
    end

    test "records a failure when no other unit has the chunk", %{pid: pid, tmp_dir: tmp_dir} do
      register(%Unit{id: "sdb1", role: :backup, root: tmp_dir, system_id: "sys_b"})

      GenServer.cast(pid, {:chunk_fetchable, @file_id, 0, "sys_b"})

      assert_receive {:failed, @file_id, 0}
      refute_received {:submitted, _, _, _, _}
    end
  end

  describe "sources" do
    test "polls only while another unit is registered", %{pid: pid, tmp_dir: tmp_dir} do
      refute pid |> :sys.get_state() |> DriveCopySource.can_poll?()

      register(%Unit{id: "sdb1", role: :backup, root: tmp_dir, system_id: "sys_b"})

      assert pid |> :sys.get_state() |> DriveCopySource.can_poll?()
    end

    test ":unit_up schedules a sweep and :unit_down cancels it", %{pid: pid, tmp_dir: tmp_dir} do
      backup = %Unit{id: "sdb1", role: :backup, root: tmp_dir, system_id: "sys_b"}

      send(pid, {:unit_up, backup})
      assert %{sweep_timers: %{"sys_b" => _}} = :sys.get_state(pid)

      send(pid, {:unit_down, backup})
      assert %{sweep_timers: timers} = :sys.get_state(pid)
      refute Map.has_key?(timers, "sys_b")
    end

    test "ignores its own role coming up", %{pid: pid} do
      send(pid, {:unit_up, %{@own | system_id: "sys_own"}})

      assert %{sweep_timers: timers} = :sys.get_state(pid)
      refute Map.has_key?(timers, "sys_own")
    end
  end

  # Registered by the test process, so it is unregistered when the test ends
  defp register(unit) do
    :ok = Units.register(unit)
    unit
  end
end
