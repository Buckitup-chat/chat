defmodule Chat.Data.File.TmpSweeperTest do
  use ExUnit.Case, async: true

  alias Chat.Data.File.TmpSweeper

  setup do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("tmp_sweeper_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    pq_dir = Path.join(tmp_dir, "pq_files")
    File.mkdir_p!(pq_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{base_dir: tmp_dir, pq_dir: pq_dir}
  end

  defp start_sweeper(base_dir, id) do
    {:ok, pid} = :gen_statem.start_link(TmpSweeper, [drive_id: id, base_dir: base_dir], [])
    :sys.get_state(pid)
    Process.sleep(50)
    pid
  end

  test "sweeps stale .tmp files on init", %{base_dir: base_dir, pq_dir: pq_dir} do
    shard_dir = Path.join([pq_dir, "ab", "f_00ab"])
    File.mkdir_p!(shard_dir)

    stale_tmp = Path.join(shard_dir, "stale.tmp")
    File.write!(stale_tmp, "stale data")
    File.touch!(stale_tmp, System.os_time(:second) - 7200)

    recent_tmp = Path.join(shard_dir, "recent.tmp")
    File.write!(recent_tmp, "recent data")

    pid = start_sweeper(base_dir, :test_sweep)

    refute File.exists?(stale_tmp)
    assert File.exists?(recent_tmp)

    :gen_statem.stop(pid)
  end

  test "periodic sweep removes stale files", %{base_dir: base_dir, pq_dir: pq_dir} do
    pid = start_sweeper(base_dir, :test_periodic)

    shard_dir = Path.join([pq_dir, "cd", "f_00cd"])
    File.mkdir_p!(shard_dir)

    stale_tmp = Path.join(shard_dir, "old.tmp")
    File.write!(stale_tmp, "old")
    File.touch!(stale_tmp, System.os_time(:second) - 7200)

    :gen_statem.cast(pid, :force_sweep)
    :sys.get_state(pid)
    Process.sleep(50)

    refute File.exists?(stale_tmp)

    :gen_statem.stop(pid)
  end

  test "keeps regular chunk files untouched", %{base_dir: base_dir, pq_dir: pq_dir} do
    shard_dir = Path.join([pq_dir, "ef", "f_00ef"])
    File.mkdir_p!(shard_dir)

    chunk_file = Path.join(shard_dir, "0000000000")
    File.write!(chunk_file, "real chunk")
    File.touch!(chunk_file, System.os_time(:second) - 7200)

    pid = start_sweeper(base_dir, :test_keep)

    assert File.exists?(chunk_file)

    :gen_statem.stop(pid)
  end
end
