defmodule ChatWeb.MainLive.Page.AdminPanel.CargoUser do
  @moduledoc """
  Creating the cargo user from the admin panel: registering its identity and sending
  each admin a dialog with the (unencrypted) backup file and a warning memo.

  Part of the `ChatWeb.MainLive.Page.AdminPanel` namespace.
  """

  import Phoenix.Component, only: [assign: 3]
  import ChatWeb.LiveHelpers, only: [process: 2]

  alias Chat.AdminRoom
  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Sync.DbBrokers
  alias Chat.Upload.UploadKey
  alias Chat.User
  alias Chat.User.UsersBroker

  def create_cargo_user(socket, {identity, backup_content, backup_entry}) do
    cargo_user =
      identity
      |> tap(&AdminRoom.store_cargo_user/1)
      |> tap(&User.register/1)
      |> tap(&UsersBroker.put/1)
      |> tap(fn _ -> DbBrokers.broadcast_refresh() end)

    socket
    |> assign(:cargo_user, cargo_user)
    |> process(fn _ ->
      AdminRoom.admin_list()
      |> Enum.each(fn admin_card ->
        dialog = %{b_key: b_key} = Dialogs.open(cargo_user, admin_card)

        destination = %{
          dialog: dialog,
          pub_key: Base.encode16(b_key, case: :lower),
          type: :dialog
        }

        file_key = UploadKey.new(destination, cargo_user.public_key, backup_entry)
        file_secret = ChunkedFiles.new_upload(file_key)

        :ok = save_file({file_key, backup_content}, {backup_entry.client_size, file_secret})

        now = Chat.TimeKeeper.now_unix()

        text =
          "The backup `#{backup_entry.client_name}` is not encrypted. Do not share it with anyone."

        %Messages.Text{text: text, timestamp: now}
        |> Dialogs.add_new_message(cargo_user, dialog)
        |> MemoIndex.add(dialog, cargo_user)

        {_index, msg} =
          backup_entry
          |> Messages.File.new(file_key, file_secret, now)
          |> Dialogs.add_new_message(cargo_user, dialog)

        FileIndex.save(file_key, dialog.a_key, msg.id, file_secret)
        FileIndex.save(file_key, dialog.b_key, msg.id, file_secret)
      end)
    end)
  end

  defp save_file({file_key, content}, {size, file_secret}) do
    ChunkedFilesMultisecret.generate(file_key, size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, max(size - 1, 0)}, size, content)
  end
end
