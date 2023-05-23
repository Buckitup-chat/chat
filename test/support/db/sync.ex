defmodule Support.Db.Sync do
  @moduledoc "Functions for synchronization"

  import ExUnit.Callbacks, only: [on_exit: 1, start_link_supervised!: 1]

  alias Chat.Card
  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db
  alias Chat.Db.Copying
  alias Chat.Db.Switching
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
    Switching.set_default(context.internal)

    on_exit(fn ->
      with db <- Chat.Db.Internal,
           pid <- Process.whereis(db),
           false <- is_nil(pid),
           true <- Process.alive?(pid) do
        Switching.set_default(Chat.Db.Internal)
      end
    end)

    alice = User.login("alice")
    bob = User.login("bob")

    User.register(alice)
    User.register(bob)

    dialog = Dialogs.find_or_open(alice, bob |> Card.from_identity())

    for time_base <- 0..500//10 do
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
    Copying.await_copied(context.internal, context.main)

    context
  end

  def copy_main_to_backup(context) do
    Copying.await_copied(context.main, context.backup)

    context
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
