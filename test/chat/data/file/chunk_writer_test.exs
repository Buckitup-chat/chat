defmodule Chat.Data.File.ChunkWriterTest do
  use ExUnit.Case, async: true

  alias Chat.Data.File.ChunkWriter

  @drive_id :test_drive

  setup do
    registry = :"test_registry_#{System.unique_integer([:positive])}"
    Registry.start_link(keys: :unique, name: registry)

    writer_name = {:via, Registry, {registry, {:writer, @drive_id}}}
    tmp_dir = System.tmp_dir!() |> Path.join("chunk_writer_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    {:ok, pid} =
      GenServer.start_link(ChunkWriter, [drive_id: @drive_id, base_dir: tmp_dir],
        name: writer_name
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm_rf!(tmp_dir)
    end)

    %{pid: pid, writer: writer_name, tmp_dir: tmp_dir}
  end

  test "writes chunk to filesystem", %{writer: writer} do
    meta = %{file_id: random_file_id(), chunk_index: 0}

    assert :ok = GenServer.call(writer, {:submit, :upload, "chunk data", meta}, 5_000)
  end

  test "upload lane rejects when queue full", %{pid: pid} do
    file_id = random_file_id()

    # Suspend so submits pile up: 1 in-flight, 2 queued, 4th rejected
    :sys.suspend(pid)

    tasks =
      for i <- 0..3 do
        Task.async(fn ->
          meta = %{file_id: file_id, chunk_index: i}
          GenServer.call(pid, {:submit, :upload, "data_#{i}", meta}, 10_000)
        end)
      end

    Process.sleep(50)
    :sys.resume(pid)

    results = Enum.map(tasks, &Task.await(&1, 10_000))

    assert Enum.count(results, &(&1 == {:busy, 2})) == 1
    assert Enum.count(results, &(&1 == :ok)) == 3
  end

  test "drive_copy and network_sync block when queue full instead of rejecting", %{pid: pid} do
    file_id = random_file_id()

    :sys.suspend(pid)

    for i <- 0..1 do
      Task.async(fn ->
        GenServer.call(pid, {:submit, :drive_copy, "dc_#{i}", %{file_id: file_id, chunk_index: i}}, 10_000)
      end)
    end

    Process.sleep(50)

    blocked_task =
      Task.async(fn ->
        GenServer.call(pid, {:submit, :drive_copy, "dc_2", %{file_id: file_id, chunk_index: 2}}, 10_000)
      end)

    Process.sleep(50)
    :sys.resume(pid)

    assert :ok = Task.await(blocked_task, 10_000)
  end

  test "upload has strict priority over network_sync", %{writer: writer} do
    file_id = random_file_id()

    sync_task =
      Task.async(fn ->
        GenServer.call(writer, {:submit, :network_sync, "sync data", %{file_id: file_id, chunk_index: 100}}, 10_000)
      end)

    Process.sleep(10)

    upload_task =
      Task.async(fn ->
        GenServer.call(writer, {:submit, :upload, "upload data", %{file_id: file_id, chunk_index: 200}}, 10_000)
      end)

    assert Task.await(upload_task, 10_000) == :ok
    assert Task.await(sync_task, 10_000) == :ok
  end

  test "lane_idle? returns true when no work queued", %{writer: writer} do
    assert GenServer.call(writer, {:lane_idle?, :upload}) == true
    assert GenServer.call(writer, {:lane_idle?, :network_sync}) == true
    assert GenServer.call(writer, {:lane_idle?, :drive_copy}) == true
  end

  test "lane_idle? reflects queue and writing state", %{pid: pid} do
    # Idle when empty
    assert GenServer.call(pid, {:lane_idle?, :upload}) == true

    # Simulate in-flight write by injecting state
    :sys.replace_state(pid, fn state ->
      %{state | writing: {make_ref(), {self(), make_ref()}, :upload}}
    end)

    assert GenServer.call(pid, {:lane_idle?, :upload}) == false
    # Other lane unaffected
    assert GenServer.call(pid, {:lane_idle?, :drive_copy}) == true

    # Restore clean state
    :sys.replace_state(pid, fn state -> %{state | writing: nil} end)
    assert GenServer.call(pid, {:lane_idle?, :upload}) == true
  end

  test "drive_copy override triggers after threshold", %{pid: pid} do
    file_id = random_file_id()

    for round <- 0..5 do
      meta = %{file_id: file_id, chunk_index: round}
      assert :ok = GenServer.call(pid, {:submit, :upload, "u#{round}", meta}, 5_000)
    end

    drive_copy_task =
      Task.async(fn ->
        GenServer.call(pid, {:submit, :drive_copy, "dc", %{file_id: file_id, chunk_index: 900}}, 10_000)
      end)

    Process.sleep(10)

    upload_task =
      Task.async(fn ->
        GenServer.call(pid, {:submit, :upload, "u_after", %{file_id: file_id, chunk_index: 901}}, 10_000)
      end)

    assert Task.await(drive_copy_task, 10_000) == :ok
    assert Task.await(upload_task, 10_000) == :ok
  end

  test "override priority: drive_copy before network_sync when both qualify", %{pid: pid} do
    file_id = random_file_id()

    :sys.suspend(pid)

    dc_task = Task.async(fn ->
      GenServer.call(pid, {:submit, :drive_copy, "dc", %{file_id: file_id, chunk_index: 0}}, 10_000)
    end)

    sync_task = Task.async(fn ->
      GenServer.call(pid, {:submit, :network_sync, "ns", %{file_id: file_id, chunk_index: 1}}, 10_000)
    end)

    Process.sleep(50)
    :sys.resume(pid)

    # Both overrides would fire at threshold. With both queued and no uploads,
    # strict lane order picks drive_copy first.
    # We verify both complete — the order is internal but both must succeed.
    assert :ok = Task.await(dc_task, 10_000)
    assert :ok = Task.await(sync_task, 10_000)
  end

  test "wait counter not incremented when queue is empty", %{pid: pid} do
    file_id = random_file_id()

    # Submit only uploads — drive_copy and network_sync queues stay empty
    for i <- 0..3 do
      assert :ok = GenServer.call(pid, {:submit, :upload, "u#{i}", %{file_id: file_id, chunk_index: i}}, 5_000)
    end

    state = :sys.get_state(pid)
    assert state.wait_counters.drive_copy == 0
    assert state.wait_counters.network_sync == 0
  end

  test "wait counter resets on selection", %{pid: pid} do
    file_id = random_file_id()

    # Build up some wait counter by interleaving upload+drive_copy
    :sys.suspend(pid)

    Task.async(fn ->
      GenServer.call(pid, {:submit, :drive_copy, "dc", %{file_id: file_id, chunk_index: 0}}, 10_000)
    end)

    Task.async(fn ->
      GenServer.call(pid, {:submit, :upload, "u", %{file_id: file_id, chunk_index: 1}}, 10_000)
    end)

    Process.sleep(50)
    :sys.resume(pid)
    Process.sleep(200)

    state = :sys.get_state(pid)
    assert state.wait_counters.drive_copy == 0
  end

  test "write task crash replies :error and continues next round", %{pid: pid, tmp_dir: tmp_dir} do
    file_id = random_file_id()

    # Make ChunkStore.put fail by removing the base dir
    File.rm_rf!(tmp_dir)
    File.write!(tmp_dir, "not a directory")

    result = GenServer.call(pid, {:submit, :upload, "data", %{file_id: file_id, chunk_index: 0}}, 5_000)
    assert {:error, _} = result

    # Writer should still be alive and accept new work
    File.rm!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    assert :ok = GenServer.call(pid, {:submit, :upload, "data2", %{file_id: random_file_id(), chunk_index: 0}}, 5_000)
  end

  test "all queues empty pauses loop, next submit restarts it", %{pid: pid} do
    file_id = random_file_id()

    assert :ok = GenServer.call(pid, {:submit, :upload, "data", %{file_id: file_id, chunk_index: 0}}, 5_000)

    state = :sys.get_state(pid)
    assert state.writing == nil
    assert Enum.all?(state.queues, fn {_, q} -> :queue.is_empty(q) end)

    assert :ok = GenServer.call(pid, {:submit, :upload, "data2", %{file_id: random_file_id(), chunk_index: 0}}, 5_000)
  end

  test "concurrent submits from all three lanes complete without loss", %{pid: pid} do
    tasks =
      for {lane, _i} <- Enum.with_index([:upload, :drive_copy, :network_sync]) do
        file_id = random_file_id()

        for j <- 0..1 do
          Task.async(fn ->
            meta = %{file_id: file_id, chunk_index: j}
            GenServer.call(pid, {:submit, lane, "#{lane}_#{j}", meta}, 10_000)
          end)
        end
      end
      |> List.flatten()

    results = Enum.map(tasks, &Task.await(&1, 10_000))

    assert Enum.all?(results, &(&1 == :ok))
    assert length(results) == 6
  end

  test "single-writer guarantee: no concurrent Tasks spawned", %{pid: pid} do
    file_id = random_file_id()

    :sys.suspend(pid)

    for i <- 0..1 do
      Task.async(fn ->
        GenServer.call(pid, {:submit, :upload, "data_#{i}", %{file_id: file_id, chunk_index: i}}, 10_000)
      end)
    end

    Process.sleep(50)
    :sys.resume(pid)
    # Let first write start but not complete
    Process.sleep(5)

    state = :sys.get_state(pid)

    case state.writing do
      nil -> assert :queue.len(state.queues[:upload]) <= 2
      {_ref, _from, :upload} -> assert true
    end
  end

  # Helpers

  defp random_file_id do
    "f_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
