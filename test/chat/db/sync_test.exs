defmodule Chat.DB.SyncTest do
  use ExUnit.Case, async: false

  alias Chat.Db.Common

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

      assert dbs.internal |> CubDB.size() == dbs.main |> CubDB.size()
      assert dbs.main |> CubDB.size() == dbs.backup |> CubDB.size()
      assert same_data?(dbs.internal, dbs.main)
      assert same_data?(dbs.main, dbs.backup)

      internal_list = dbs.internal |> files_list()
      main_list = dbs.main |> files_list()
      backup_list = dbs.backup |> files_list()

      assert internal_list == main_list
      assert main_list == backup_list
    end
  end

  defp same_data?(src, dst) do
    dst
    |> CubDB.select()
    |> Enum.all?(fn {key, value} ->
      src |> CubDB.get(key) == value
    end)
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
      assert 1112 = dbs.internal |> CubDB.size()

      assert 222 =
               dbs.internal
               |> files_list()
               |> Enum.count()
    end
  end

  def make_dbs(context) do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join(Enigma.hash(context.test |> to_string()) |> Base.encode16())

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    [:internal, :main, :backup]
    |> Enum.map(fn key ->
      db_path = Path.join(tmp_dir, key |> to_string())
      File.mkdir_p!(db_path)

      db_key = :"Chat.TestDb.#{key |> to_string()}"

      Chat.Db.supervise(db_key, db_path)
      |> Enum.each(fn spec ->
        spec
        |> Supervisor.child_spec(id: :crypto.strong_rand_bytes(3))
        |> start_link_supervised!()
      end)

      db_key |> CubDB.set_auto_compact(false)

      {key, db_key}
    end)
    |> Map.new()
    |> Map.merge(context)
  end

  def fill_interal(context) do
    Chat.Db.Switching.set_default(context.internal)

    on_exit(fn ->
      with db <- Chat.Db.Internal,
           pid <- Process.whereis(db),
           false <- is_nil(pid),
           true <- Process.alive?(pid) do
        Chat.Db.Switching.set_default(Chat.Db.Internal)
      end
    end)

    alice = Chat.User.login("alice")
    bob = Chat.User.login("bob")

    Chat.User.register(alice)
    Chat.User.register(bob)

    dialog = Chat.Dialogs.find_or_open(alice, bob |> Chat.Card.from_identity())

    for time_base <- 0..1100//10 do
      generate_content(alice, bob, dialog, time_base)
    end

    context
  end

  defp generate_content(alice, bob, dialog, time_base) do
    "hello" |> text_message(from: alice, in: dialog, time: time_base + 0)
    "hi Alice" |> text_message(from: bob, in: dialog, time: time_base + 1)

    "long text "
    |> String.duplicate(200)
    |> text_message(from: alice, in: dialog, time: time_base + 2)

    file_message(from: alice, in: dialog, time: time_base + 3)
    file_message(from: bob, in: dialog, time: time_base + 4)
  end

  def copy_internal_to_main(context) do
    Chat.Db.Copying.await_copied(context.internal, context.main)

    context
  end

  def copy_main_to_backup(context) do
    Chat.Db.Copying.await_copied(context.main, context.backup)

    context
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

  defp text_message(msg, opts) do
    [time, from, dialog] = [:time, :from, :in] |> Enum.map(&Keyword.fetch!(opts, &1))

    msg
    |> Chat.Messages.Text.new(time)
    |> Chat.Dialogs.add_new_message(from, dialog)
  end

  defp file_message(opts) do
    [time, from, dialog] = [:time, :from, :in] |> Enum.map(&Keyword.fetch!(opts, &1))
    random_size = :rand.uniform(2 * 1024 * 2014)
    content = :crypto.strong_rand_bytes(random_size)

    with file_info <- %{
           size: random_size,
           time: time
         },
         entry <- entry(file_info),
         destination <- destination(dialog),
         file_key <- Chat.Upload.UploadKey.new(destination, dialog.b_key, entry),
         file_secret <- Chat.ChunkedFiles.new_upload(file_key),
         :ok <- save({file_key, content}, {file_info.size, file_secret}) do
      entry
      |> Chat.Messages.File.new(file_key, file_secret, time)
      |> Chat.Dialogs.add_new_message(from, dialog)
    end
  end

  defp files_list(db) do
    db
    |> CubDB.data_dir()
    |> then(&"#{&1}_files")
    |> Chat.FileFs.relative_filenames()
    |> Enum.sort()
  end

  defp destination(%Chat.Dialogs.Dialog{b_key: b_key} = dialog) do
    %{
      dialog: dialog,
      pub_key: Base.encode16(b_key, case: :lower),
      type: :dialog
    }
  end

  defp entry(file_info) do
    %{
      client_last_modified: file_info.time,
      client_name: "random file",
      client_relative_path: nil,
      client_size: file_info.size,
      client_type: "text/plain"
    }
  end

  defp save({file_key, share_key}, {file_size, file_secret}) do
    Chat.ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    Chat.ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end
end
