defmodule Chat.Db.CopyingTest do
  use ExUnit.Case, async: false

  alias Chat.ChunkedFiles
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Db.Copying
  alias Chat.Db.MainDbSupervisor

  test "one way copying should make a perfect copy" do
    make_some_data()

    start_second_db()
    |> copy_from_first_to_second()
    |> assert_first_is_equal_second()
    |> stop_second_db()
  end

  defp make_some_data do
    for i <- 1..200 do
      Db.put({:some_test_data, UUID.uuid4()}, i)
    end

    key = UUID.uuid4()
    _secret = ChunkedFiles.new_upload(key)

    first = "some part of info "
    second = "another part"

    ChunkedFiles.save_upload_chunk(key, {1, 18}, first)
    ChunkedFiles.save_upload_chunk(key, {19, 30}, second)

    ChangeTracker.await()
  end

  defp start_second_db do
    {:ok, pid} =
      "#{Db.file_path()}-main"
      |> MainDbSupervisor.start_link()

    pid
  end

  defp copy_from_first_to_second(pid) do
    Copying.await_copied(Chat.Db.InternalDb, Chat.Db.MainDb)
    Process.sleep(1000)

    pid
  end

  defp assert_first_is_equal_second(pid) do
    internal_size = CubDB.size(Chat.Db.InternalDb)
    second_size = CubDB.size(Chat.Db.MainDb)

    assert second_size == internal_size

    internal_dir_hash = Chat.Db.InternalDb |> file_path() |> dir_hash()
    second_dir_hash = Chat.Db.MainDb |> file_path() |> dir_hash()

    assert internal_dir_hash == second_dir_hash

    pid
  end

  defp stop_second_db(pid) do
    Supervisor.stop(pid)
  end

  defp file_path(db) do
    CubDB.data_dir(db) <> "_files"
  end

  defp dir_hash(path) do
    System.cmd("sh", ["-c", "ls -aR #{path} | sha256sum"])
    |> elem(1)
  end
end
