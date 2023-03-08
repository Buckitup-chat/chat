defmodule Chat.Db.CopyingTest do
  use ExUnit.Case, async: false

  alias Chat.ChunkedFiles
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Db.Copying
  alias Chat.Db.InternalDb
  alias Chat.Db.MainDb
  alias Chat.Db.MainDbSupervisor

  setup_all do
    Db.db()
    |> CubDB.clear()

    File.rm_rf!("priv/test_admin_db")
    File.rm_rf!("priv/test_db")

    :ok
  end

  test "one way copying should make a perfect copy" do
    make_some_data()

    start_second_db()
    |> copy_from_first_to_second()
    |> assert_first_is_equal_second()
    |> stop_second_db()
  end

  test "is able to copy only part of the data" do
    keys =
      make_some_data()
      |> Enum.take(10)
      |> MapSet.new()

    start_second_db()
    |> copy_from_first_to_second(keys)
    |> refute_first_is_equal_second()
    |> stop_second_db()
  end

  defp make_some_data do
    keys =
      Enum.reduce(1..200, [], fn i, keys ->
        key = {:some_test_data, UUID.uuid4()}

        Db.put(key, i)

        [key | keys]
      end)

    key = UUID.uuid4()
    _secret = ChunkedFiles.new_upload(key)

    first = "some part of info "
    second = "another part"

    ChunkedFiles.save_upload_chunk(key, {1, 18}, first)
    ChunkedFiles.save_upload_chunk(key, {19, 30}, second)

    ChangeTracker.await()

    keys
  end

  defp start_second_db do
    {:ok, pid} =
      "#{Db.file_path()}-main"
      |> MainDbSupervisor.start_link()

    Chat.Db.MainDb
    |> file_path()
    |> File.mkdir()

    pid
  end

  defp copy_from_first_to_second(pid, keys \\ nil) do
    Copying.await_copied(Chat.Db.InternalDb, Chat.Db.MainDb, keys)
    Process.sleep(1000)

    pid
  end

  defp assert_first_is_equal_second(pid) do
    assert CubDB.size(MainDb) == CubDB.size(InternalDb)
    assert db_files_dir_hash(InternalDb) == db_files_dir_hash(MainDb)

    pid
  end

  defp refute_first_is_equal_second(pid) do
    refute CubDB.size(MainDb) == CubDB.size(InternalDb)
    refute db_files_dir_hash(InternalDb) == db_files_dir_hash(MainDb)

    pid
  end

  defp stop_second_db(pid) do
    Supervisor.stop(pid)
  end

  defp file_path(db) do
    CubDB.data_dir(db) <> "_files"
  end

  defp db_files_dir_hash(db) do
    db
    |> file_path()
    |> dir_hash()
  end

  defp dir_hash(path) do
    System.cmd("sh", ["-c", "cd #{path} && ls -aR . | sha256sum"])
    |> elem(0)
  end
end
