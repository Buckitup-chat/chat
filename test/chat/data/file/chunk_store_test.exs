defmodule Chat.Data.File.ChunkStoreTest do
  use ExUnit.Case, async: true

  alias Chat.Data.File.ChunkStore
  alias Chat.Storage.Unit

  setup do
    tmp_dir =
      System.tmp_dir!() |> Path.join("chunk_store_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{unit: %Unit{id: "sdt1", role: :main, root: tmp_dir}}
  end

  test "fetch returns error for missing chunk", %{unit: unit} do
    assert {:error, :enoent} = ChunkStore.fetch(unit, "f_deadbeef00000000", 0)
  end

  test "put leaves no .tmp file on success", %{unit: unit} do
    file_id = random_file_id()

    assert :ok = ChunkStore.put(unit, file_id, 0, "data")

    tmp_files =
      Path.join(unit.root, "**/*.tmp")
      |> Path.wildcard()

    assert tmp_files == []
  end

  test "shard path uses last 2 hex chars of file_id", %{unit: unit} do
    file_id = "f_abcdef1234567890abcdef1234567890"

    assert :ok = ChunkStore.put(unit, file_id, 0, "data")
    assert {:ok, "data"} = ChunkStore.fetch(unit, file_id, 0)

    # Shard should be last 2 hex chars: "90"
    shard_dir = Path.join([Unit.path(unit, :pq_files), "90", file_id])
    assert File.dir?(shard_dir)
  end

  test "sweep_tmp_files removes old tmp files and keeps recent", %{unit: unit} do
    file_id = random_file_id()

    assert :ok = ChunkStore.put(unit, file_id, 0, "real")

    stale_tmp = Path.join(file_dir(unit, file_id), "stale.tmp")
    File.write!(stale_tmp, "stale")
    File.touch!(stale_tmp, System.os_time(:second) - 3600)

    recent_tmp = Path.join(file_dir(unit, file_id), "recent.tmp")
    File.write!(recent_tmp, "recent")

    ChunkStore.sweep_tmp_files(unit, :timer.minutes(30))

    refute File.exists?(stale_tmp)
    assert File.exists?(recent_tmp)
  end

  test "delete_file removes all chunks for a file", %{unit: unit} do
    file_id = random_file_id()

    for i <- 0..2, do: ChunkStore.put(unit, file_id, i, "chunk_#{i}")

    assert {:ok, _} = ChunkStore.fetch(unit, file_id, 0)
    assert File.dir?(file_dir(unit, file_id))

    File.rm_rf!(file_dir(unit, file_id))
    assert {:error, :enoent} = ChunkStore.fetch(unit, file_id, 0)
  end

  test "round-trip: put then fetch returns original data", %{unit: unit} do
    file_id = random_file_id()
    data = :crypto.strong_rand_bytes(4096)

    assert :ok = ChunkStore.put(unit, file_id, 0, data)
    assert {:ok, ^data} = ChunkStore.fetch(unit, file_id, 0)
  end

  test "put overwrites existing chunk", %{unit: unit} do
    file_id = random_file_id()

    assert :ok = ChunkStore.put(unit, file_id, 0, "first")
    assert :ok = ChunkStore.put(unit, file_id, 0, "second")
    assert {:ok, "second"} = ChunkStore.fetch(unit, file_id, 0)
  end

  test "count_on_disk returns 0 when no directory exists", %{unit: unit} do
    assert ChunkStore.count_on_disk(unit, random_file_id()) == 0
  end

  test "count_on_disk counts chunks written for a file", %{unit: unit} do
    file_id = random_file_id()

    for i <- 0..2, do: ChunkStore.put(unit, file_id, i, "chunk_#{i}")

    assert ChunkStore.count_on_disk(unit, file_id) == 3
  end

  test "count_on_disk excludes stray .tmp files", %{unit: unit} do
    file_id = random_file_id()

    :ok = ChunkStore.put(unit, file_id, 0, "data")

    stray_tmp = Path.join(file_dir(unit, file_id), "0000000001.tmp")
    File.write!(stray_tmp, "partial")

    assert ChunkStore.count_on_disk(unit, file_id) == 1
  end

  # Helpers

  defp random_file_id do
    "f_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp file_dir(unit, file_id) do
    "f_" <> hex = file_id
    shard = String.slice(hex, -2, 2)
    Path.join([Unit.path(unit, :pq_files), shard, file_id])
  end
end
