defmodule Chat.Db.DbTypeTest do
  use ExUnit.Case, async: false

  alias Chat.Db
  alias Chat.Db.{DbType, InternalDb, MainDb, MainDbSupervisor, MediaDbSupervisor}

  setup do
    CubDB.clear(Db.db())
  end

  test "sets and gets db type" do
    MainDbSupervisor.start_link("#{Db.file_path()}-main")
    MediaDbSupervisor.start_link([BackupDb, "priv/test_backup_db"])

    refute DbType.get(InternalDb)
    DbType.put(InternalDb, "main_db")
    assert DbType.get(InternalDb) == "main_db"

    refute DbType.get(MainDb)
    DbType.put(MainDb, "main_db")
    assert DbType.get(MainDb) == "main_db"

    refute DbType.get(BackupDb)
    DbType.put(BackupDb, "backup_db")
    assert DbType.get(BackupDb) == "backup_db"
  end
end
