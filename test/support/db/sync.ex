defmodule Support.Db.Sync do
  @moduledoc "Functions for synchronization"

  import ExUnit.Callbacks, only: [on_exit: 1, start_link_supervised!: 1]

  alias Chat.Card
  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db
  alias Chat.Db.Common
  alias Chat.Db.Copying
  alias Chat.Db.Scope.Full, as: FullScope
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Upload.UploadKey
  alias Chat.User

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

      Db.supervise(db_key, db_path)
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
    prev_settings = switch_on(context.internal)
    on_exit(fn -> restore_settings(prev_settings) end)

    alice = User.login("alice")
    bob = User.login("bob")

    User.register(alice)
    User.register(bob)

    dialog = Dialogs.find_or_open(alice, bob |> Card.from_identity())

    0..500//10
    |> Task.async_stream(
      fn time_base ->
        generate_content(alice, bob, dialog, time_base)
      end,
      max_concurrency: 55
    )
    |> Enum.to_list()

    context.internal |> CubDB.file_sync()

    context
  end

  def copy_internal_to_main(context) do
    keys = FullScope.keys(context.internal)
    # {time, _} = :timer.tc(fn -> Copying.await_copied(context.internal, context.main) end)
    # time |> IO.inspect(label: "copy_internal_to_main")
    Copying.await_copied(context.internal, context.main)

    context
    |> Map.put(:internal_to_main_keys, keys)
  end

  def copy_main_to_backup(context) do
    keys = FullScope.keys(context.main)
    # {time, _} = :timer.tc(fn -> Copying.await_copied(context.main, context.backup) end)
    # time |> IO.inspect(label: "copy_main_to_backup")
    Copying.await_copied(context.main, context.backup)

    context
    |> Map.put(:main_to_backup_keys, keys)
  end

  defp switch_on(name) do
    queue_name = Common.names(name, :queue)
    status_relay_name = Common.names(name, :status)

    prev_settings = %{
      queue_name: Common.get_chat_db_env(:data_queue),
      status_relay_name: Common.get_chat_db_env(:data_dry),
      files_base_dir: Common.get_chat_db_env(:files_base_dir),
      data_pid: Common.get_chat_db_env(:data_pid)
    }

    Common.put_chat_db_env(:data_queue, queue_name)
    Common.put_chat_db_env(:data_pid, name)
    Common.put_chat_db_env(:files_base_dir, CubDB.data_dir(name) <> "_files")
    Common.put_chat_db_env(:data_dry, status_relay_name)

    Chat.Ordering.reset()

    prev_settings
  end

  defp restore_settings(prev_settings) do
    Common.put_chat_db_env(:data_queue, prev_settings[:queue_name])
    Common.put_chat_db_env(:data_pid, prev_settings[:data_pid])
    Common.put_chat_db_env(:files_base_dir, prev_settings[:files_base_dir])
    Common.put_chat_db_env(:data_dry, prev_settings[:status_relay_name])

    Chat.Ordering.reset()
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

    msg
    |> Messages.Text.new(time)
    |> Dialogs.add_new_message(from, dialog)
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
         file_key <- UploadKey.new(destination, dialog.b_key, entry),
         file_secret <- ChunkedFiles.new_upload(file_key),
         :ok <- save({file_key, content}, {file_info.size, file_secret}) do
      entry
      |> Messages.File.new(file_key, file_secret, time)
      |> Dialogs.add_new_message(from, dialog)
    end
  end

  defp destination(%Dialogs.Dialog{b_key: b_key} = dialog) do
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
    ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end
end
