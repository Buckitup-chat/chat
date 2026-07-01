defmodule Chat.Data.File.UploadSourceTest do
  use ExUnit.Case, async: true

  alias Chat.Data.File.ChunkWriter

  @drive_id :test_upload_drive

  setup do
    registry = :"test_registry_#{System.unique_integer([:positive])}"
    Registry.start_link(keys: :unique, name: registry)

    writer_name = {:via, Registry, {registry, {:writer, @drive_id}}}
    tmp_dir = System.tmp_dir!() |> Path.join("upload_source_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    {:ok, writer_pid} =
      GenServer.start_link(ChunkWriter, [drive_id: @drive_id, base_dir: tmp_dir],
        name: writer_name
      )

    on_exit(fn ->
      if Process.alive?(writer_pid), do: GenServer.stop(writer_pid)
      File.rm_rf!(tmp_dir)
    end)

    %{writer: writer_name, writer_pid: writer_pid}
  end

  test "submit delegates to ChunkWriter with :upload lane", %{writer: writer} do
    file_id = random_file_id()
    meta = %{file_id: file_id, chunk_index: 0}

    assert :ok = ChunkWriter.submit(writer, :upload, "data", meta)
  end

  test "returns {:busy, 2} when ChunkWriter upload lane is full", %{writer_pid: pid, writer: writer} do
    file_id = random_file_id()

    :sys.suspend(pid)

    tasks =
      for i <- 0..3 do
        Task.async(fn ->
          ChunkWriter.submit(writer, :upload, "d#{i}", %{file_id: file_id, chunk_index: i})
        end)
      end

    Process.sleep(50)
    :sys.resume(pid)

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.any?(results, &(&1 == {:busy, 2}))
  end

  # Helpers

  defp random_file_id do
    "f_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
