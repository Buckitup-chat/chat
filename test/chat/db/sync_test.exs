defmodule Chat.DB.SyncTest do
  use ChatTest.IsolatedDataCase, dbs: [:internal, :main, :backup]

  alias Chat.Card
  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db.Common
  alias Chat.Db.Copying
  alias Chat.Db.Scope.Full, as: FullScope
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Upload.UploadKey
  alias Chat.User

  setup_all context do
    internal = db_name(context, :internal)
    main = db_name(context, :main)
    backup = db_name(context, :backup)

    context |> use_db(:internal)

    alice = User.login("alice")
    bob = User.login("bob")
    User.register(alice)
    User.register(bob)

    dialog = Dialogs.find_or_open(alice, bob |> Card.from_identity())

    0..500//10
    |> Task.async_stream(
      fn time_base -> generate_content(alice, bob, dialog, time_base) end,
      max_concurrency: 55
    )
    |> Stream.run()

    await_writes_complete(internal)

    internal_to_main_keys = FullScope.keys(internal)
    Copying.await_copied(internal, main)

    main_to_backup_keys = FullScope.keys(main)
    Copying.await_copied(main, backup)

    context
    |> Map.put(:internal_to_main_keys, internal_to_main_keys)
    |> Map.put(:main_to_backup_keys, main_to_backup_keys)
  end

  test "dbs are working", context do
    assert_alive(context, :internal)
    assert_alive(context, :main)
    assert_alive(context, :backup)
  end

  test "internal filled", context do
    internal = db_name(context, :internal)
    assert 510 < CubDB.size(internal)

    assert 102 =
             internal
             |> files_list()
             |> Enum.count()
  end

  test "internal to main to backup copying", context do
    internal = db_name(context, :internal)
    main = db_name(context, :main)
    backup = db_name(context, :backup)

    assert_copied(context.internal_to_main_keys, main)
    assert_copied(context.main_to_backup_keys, backup)

    assert internal |> files_list() == main |> files_list()
    assert main |> files_list() == backup |> files_list()
  end

  defp assert_alive(context, db_key) do
    db = db_name(context, db_key)

    [db, Common.names(db, :queue), Common.names(db, :writer), Common.names(db, :status)]
    |> Enum.each(fn p_name ->
      refute is_nil(p_name)
      assert is_pid(pid = Process.whereis(p_name)), "#{p_name} not a process"
      assert Process.alive?(pid)
    end)
  end

  defp assert_copied(src, dst_db) do
    dst = dst_db |> FullScope.keys() |> MapSet.new()
    diff = MapSet.difference(MapSet.new(src), dst)
    assert MapSet.size(diff) == 0, "#{inspect(diff)} not copied"
  end

  defp files_list(db) do
    db
    |> CubDB.data_dir()
    |> then(&"#{&1}_files")
    |> Chat.FileFs.list_all_db_keys()
    |> Enum.sort()
  end

  defp await_writes_complete(db, prev \\ nil) do
    size = CubDB.size(db)

    if size == prev do
      CubDB.file_sync(db)
    else
      Process.sleep(100)
      await_writes_complete(db, size)
    end
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

  defp text_message(msg, opts) do
    [time, from, dialog] = [:time, :from, :in] |> Enum.map(&Keyword.fetch!(opts, &1))
    msg |> Messages.Text.new(time) |> Dialogs.add_new_message(from, dialog)
  end

  defp file_message(opts) do
    [time, from, dialog] = [:time, :from, :in] |> Enum.map(&Keyword.fetch!(opts, &1))
    random_size = :rand.uniform(2 * 1024 * 2014)
    content = :crypto.strong_rand_bytes(random_size)

    with file_info <- %{size: random_size, time: time},
         entry <- entry(file_info),
         destination <- destination(dialog),
         file_key <- UploadKey.new(destination, dialog.b_key, entry),
         file_secret <- ChunkedFiles.new_upload(file_key),
         :ok <- save({file_key, content}, {file_info.size, file_secret}) do
      entry
      |> Messages.File.new(file_key, file_secret, time)
      |> Dialogs.add_new_message(from, dialog)
    end
  end

  defp destination(%Dialogs.Dialog{b_key: b_key} = dialog) do
    %{dialog: dialog, pub_key: Base.encode16(b_key, case: :lower), type: :dialog}
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
    ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end
end
