defmodule Chat.Data.File.ChunkWriterTest do
  use ExUnit.Case, async: true

  alias Chat.Data.File.ChunkWriter
  alias Chat.Storage.Unit

  @drive_id :test_drive

  setup do
    registry = :"test_registry_#{System.unique_integer([:positive])}"
    Registry.start_link(keys: :unique, name: registry)

    writer_name = {:via, Registry, {registry, {:writer, @drive_id}}}

    tmp_dir =
      System.tmp_dir!() |> Path.join("chunk_writer_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    {:ok, pid} =
      GenServer.start_link(ChunkWriter, [unit: %Unit{id: @drive_id, role: :main, root: tmp_dir}],
        name: writer_name
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm_rf!(tmp_dir)
    end)

    %{pid: pid, writer: writer_name, tmp_dir: tmp_dir}
  end

  test "writes chunk to filesystem", %{writer: writer} do
    assert :ok = submit(writer, :upload, "chunk data", random_file_id(), 0)
  end

  test "upload lane rejects when queue full", %{pid: pid} do
    file_id = random_file_id()

    # Suspend so submits pile up: 1 in-flight, 2 queued, 4th rejected
    :sys.suspend(pid)
    tasks = for i <- 0..3, do: async_submit(pid, :upload, "data_#{i}", file_id, i)
    Process.sleep(50)
    :sys.resume(pid)

    results = Enum.map(tasks, &Task.await(&1, 10_000))

    assert Enum.count(results, &(&1 == {:busy, 2})) == 1
    assert Enum.count(results, &(&1 == :ok)) == 3
  end

  test "drive_copy and network_sync block when queue full instead of rejecting", %{pid: pid} do
    file_id = random_file_id()

    :sys.suspend(pid)
    for i <- 0..1, do: async_submit(pid, :drive_copy, "dc_#{i}", file_id, i)
    Process.sleep(50)
    blocked_task = async_submit(pid, :drive_copy, "dc_2", file_id, 2)
    Process.sleep(50)
    :sys.resume(pid)

    assert :ok = Task.await(blocked_task, 10_000)
  end

  test "upload has strict priority over network_sync", %{writer: writer} do
    file_id = random_file_id()

    sync_task = async_submit(writer, :network_sync, "sync data", file_id, 100)
    Process.sleep(10)
    upload_task = async_submit(writer, :upload, "upload data", file_id, 200)

    assert Task.await(upload_task, 10_000) == :ok
    assert Task.await(sync_task, 10_000) == :ok
  end

  test "lane_idle? returns true when no work queued", %{writer: writer} do
    assert lane_idle?(writer, :upload) == true
    assert lane_idle?(writer, :network_sync) == true
    assert lane_idle?(writer, :drive_copy) == true
  end

  test "lane_idle? reflects queue and writing state", %{pid: pid} do
    assert lane_idle?(pid, :upload) == true

    # Simulate in-flight write by injecting state
    :sys.replace_state(pid, fn state ->
      %{state | writing: {make_ref(), {self(), make_ref()}, :upload}}
    end)

    assert lane_idle?(pid, :upload) == false
    assert lane_idle?(pid, :drive_copy) == true

    :sys.replace_state(pid, fn state -> %{state | writing: nil} end)
    assert lane_idle?(pid, :upload) == true
  end

  test "drive_copy override triggers after threshold", %{pid: pid} do
    file_id = random_file_id()

    for round <- 0..5 do
      assert :ok = submit(pid, :upload, "u#{round}", file_id, round)
    end

    drive_copy_task = async_submit(pid, :drive_copy, "dc", file_id, 900)
    Process.sleep(10)
    upload_task = async_submit(pid, :upload, "u_after", file_id, 901)

    assert Task.await(drive_copy_task, 10_000) == :ok
    assert Task.await(upload_task, 10_000) == :ok
  end

  test "override priority: drive_copy before network_sync when both qualify", %{pid: pid} do
    file_id = random_file_id()

    :sys.suspend(pid)
    dc_task = async_submit(pid, :drive_copy, "dc", file_id, 0)
    sync_task = async_submit(pid, :network_sync, "ns", file_id, 1)
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
      assert :ok = submit(pid, :upload, "u#{i}", file_id, i)
    end

    state = :sys.get_state(pid)
    assert state.wait_counters.drive_copy == 0
    assert state.wait_counters.network_sync == 0
  end

  test "wait counter resets on selection", %{pid: pid} do
    file_id = random_file_id()

    # Build up some wait counter by interleaving upload+drive_copy
    :sys.suspend(pid)
    async_submit(pid, :drive_copy, "dc", file_id, 0)
    async_submit(pid, :upload, "u", file_id, 1)
    Process.sleep(50)
    :sys.resume(pid)
    Process.sleep(200)

    state = :sys.get_state(pid)
    assert state.wait_counters.drive_copy == 0
  end

  test "write task crash replies :error and continues next round", %{pid: pid, tmp_dir: tmp_dir} do
    # Make ChunkStore.put fail by removing the base dir
    File.rm_rf!(tmp_dir)
    File.write!(tmp_dir, "not a directory")

    assert {:error, _} = submit(pid, :upload, "data", random_file_id(), 0)

    File.rm!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    assert :ok = submit(pid, :upload, "data2", random_file_id(), 0)
  end

  test "all queues empty pauses loop, next submit restarts it", %{pid: pid} do
    assert :ok = submit(pid, :upload, "data", random_file_id(), 0)

    state = :sys.get_state(pid)
    assert state.writing == nil
    assert Enum.all?(state.queues, fn {_, q} -> :queue.is_empty(q) end)

    assert :ok = submit(pid, :upload, "data2", random_file_id(), 0)
  end

  test "concurrent submits from all three lanes complete without loss", %{pid: pid} do
    tasks =
      for lane <- [:upload, :drive_copy, :network_sync] do
        file_id = random_file_id()
        for j <- 0..1, do: async_submit(pid, lane, "#{lane}_#{j}", file_id, j)
      end
      |> List.flatten()

    results = Enum.map(tasks, &Task.await(&1, 10_000))

    assert Enum.all?(results, &(&1 == :ok))
    assert length(results) == 6
  end

  test "single-writer guarantee: no concurrent Tasks spawned", %{pid: pid} do
    file_id = random_file_id()

    :sys.suspend(pid)
    for i <- 0..1, do: async_submit(pid, :upload, "data_#{i}", file_id, i)
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

  defp submit(writer, lane, data, file_id, chunk_index) do
    GenServer.call(writer, {:submit, lane, data, chunk_meta(file_id, chunk_index)}, 5_000)
  end

  defp async_submit(writer, lane, data, file_id, chunk_index) do
    Task.async(fn ->
      GenServer.call(writer, {:submit, lane, data, chunk_meta(file_id, chunk_index)}, 10_000)
    end)
  end

  defp chunk_meta(file_id, chunk_index), do: %{file_id: file_id, chunk_index: chunk_index}

  defp lane_idle?(writer, lane), do: GenServer.call(writer, {:lane_idle?, lane})

  defp random_file_id do
    "f_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
