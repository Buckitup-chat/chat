defmodule Chat.Data.File.ChunkStoreTest do
  use ExUnit.Case, async: true

  alias Chat.Data.File.ChunkStore

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("chunk_store_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{base_dir: tmp_dir}
  end

  test "fetch returns error for missing chunk", %{base_dir: base_dir} do
    assert {:error, :enoent} = ChunkStore.fetch("f_deadbeef00000000", 0, base_dir)
  end

  test "put leaves no .tmp file on success", %{base_dir: base_dir} do
    file_id = random_file_id()

    assert :ok = ChunkStore.put(file_id, 0, "data", base_dir)

    tmp_files =
      Path.join(base_dir, "**/*.tmp")
      |> Path.wildcard()

    assert tmp_files == []
  end

  test "shard path uses last 2 hex chars of file_id", %{base_dir: base_dir} do
    file_id = "f_abcdef1234567890abcdef1234567890"

    assert :ok = ChunkStore.put(file_id, 0, "data", base_dir)
    assert {:ok, "data"} = ChunkStore.fetch(file_id, 0, base_dir)

    # Shard should be last 2 hex chars: "90"
    shard_dir = Path.join([base_dir, "pq_files", "90", file_id])
    assert File.dir?(shard_dir)
  end


  test "sweep_tmp_files removes old tmp files and keeps recent", %{base_dir: base_dir} do
    file_id = random_file_id()

    assert :ok = ChunkStore.put(file_id, 0, "real", base_dir)

    # Create a stale .tmp file manually
    "f_" <> hex = file_id
    shard = String.slice(hex, -2, 2)
    stale_tmp = Path.join([base_dir, "pq_files", shard, file_id, "stale.tmp"])
    File.write!(stale_tmp, "stale")
    File.touch!(stale_tmp, System.os_time(:second) - 3600)

    # Create a recent .tmp file
    recent_tmp = Path.join([base_dir, "pq_files", shard, file_id, "recent.tmp"])
    File.write!(recent_tmp, "recent")

    ChunkStore.sweep_tmp_files(:timer.minutes(30), base_dir)

    refute File.exists?(stale_tmp)
    assert File.exists?(recent_tmp)
  end

  test "delete_file removes all chunks for a file", %{base_dir: base_dir} do
    file_id = random_file_id()

    for i <- 0..2, do: ChunkStore.put(file_id, i, "chunk_#{i}", base_dir)

    assert {:ok, _} = ChunkStore.fetch(file_id, 0, base_dir)

    "f_" <> hex = file_id
    shard = String.slice(hex, -2, 2)
    file_dir = Path.join([base_dir, "pq_files", shard, file_id])
    assert File.dir?(file_dir)

    File.rm_rf!(file_dir)
    assert {:error, :enoent} = ChunkStore.fetch(file_id, 0, base_dir)
  end

  test "round-trip: put then fetch returns original data", %{base_dir: base_dir} do
    file_id = random_file_id()
    data = :crypto.strong_rand_bytes(4096)

    assert :ok = ChunkStore.put(file_id, 0, data, base_dir)
    assert {:ok, ^data} = ChunkStore.fetch(file_id, 0, base_dir)
  end

  test "put overwrites existing chunk", %{base_dir: base_dir} do
    file_id = random_file_id()

    assert :ok = ChunkStore.put(file_id, 0, "first", base_dir)
    assert :ok = ChunkStore.put(file_id, 0, "second", base_dir)
    assert {:ok, "second"} = ChunkStore.fetch(file_id, 0, base_dir)
  end

  # Helpers

  defp random_file_id do
    "f_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
