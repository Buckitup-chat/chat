defmodule Chat.DB.SyncTest do
  use ExUnit.Case, async: false

  import Support.Db.Sync

  alias Chat.Db.Common
  alias Chat.Db.Copying

  describe "sync" do
    setup [
      :make_dbs,
      :fill_interal,
      :copy_internal_to_main,
      :copy_main_to_backup
    ]

    test "internal to main to backup copying", dbs do
      assert_alive(dbs.internal)
      assert_alive(dbs.main)
      assert_alive(dbs.backup)

      assert_copied(dbs.internal_to_main_keys, dbs.main)
      assert_copied(dbs.main_to_backup_keys, dbs.backup)

      internal_list = dbs.internal |> files_list()
      main_list = dbs.main |> files_list()
      backup_list = dbs.backup |> files_list()

      assert internal_list == main_list
      assert main_list == backup_list
    end
  end

  describe "preparation" do
    setup [
      :make_dbs,
      :fill_interal
    ]

    test "dbs are working", dbs do
      assert_alive(dbs.internal)
      assert_alive(dbs.main)
      assert_alive(dbs.backup)
    end

    test "internal filled", dbs do
      assert 510 < dbs.internal |> CubDB.size()

      assert 102 =
               dbs.internal
               |> files_list()
               |> Enum.count()
    end
  end

  defp assert_alive(db) do
    [
      db,
      Common.names(db, :queue),
      Common.names(db, :writer),
      Common.names(db, :status)
    ]
    |> Enum.each(fn p_name ->
      refute is_nil(p_name)
      assert is_pid(pid = Process.whereis(p_name)), "#{p_name} not a process"
      assert Process.alive?(pid)
    end)
  end

  defp assert_copied(src, dst_db) do
    dst =
      dst_db
      |> Copying.get_data_keys_set()
      |> MapSet.new()

    diff = MapSet.difference(src |> MapSet.new(), dst)

    assert MapSet.size(diff) == 0,
           "#{inspect(diff)} not copied "
  end

  defp files_list(db) do
    db
    |> CubDB.data_dir()
    |> then(&"#{&1}_files")
    |> Chat.FileFs.relative_filenames()
    |> Enum.sort()
  end
end
