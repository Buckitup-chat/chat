defmodule Chat.KeyShare do
  @moduledoc "Manipulate social sharing keys"

  alias Chat.Identity
  alias Chat.{Actor, ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Upload.UploadKey
  alias Chat.{Dialogs, Dialogs.Dialog, Messages}

  alias Phoenix.PubSub

  def generate_key_shares(
        {%Identity{private_key: private_key, public_key: public_key} = me, users}
      ) do
    share_count = Enum.count(users)
    base_key = Actor.new(me, [], %{}) |> Actor.to_encrypted_json("") |> Base.encode64()
    len_part = ceil(String.length(base_key) / share_count)

    for i <- 0..(share_count - 1), into: [] do
      start_idx = i * len_part
      end_idx = start_idx + len_part - 1

      %{
        user: Enum.at(users, i),
        key:
          String.slice(base_key, start_idx..end_idx)
          |> Enigma.encrypt(private_key, public_key)
      }
    end
  end

  def send_shares(shares, {me, time_offset}) do
    shares
    |> Enum.each(fn share ->
      with dialog <- Dialogs.find_or_open(me, share.user),
           file_info <- %{
             size: byte_size(share.key),
             time: Chat.Time.monotonic_to_unix(time_offset)
           },
           entry <- entry(file_info, me),
           destination <- destination(dialog),
           file_key <- UploadKey.new(destination, dialog.b_key, entry),
           file_secret <- ChunkedFiles.new_upload(file_key) do
        save({file_key, share.key}, {file_info.size, file_secret})
        send(entry, dialog, me, {file_key, file_secret, file_info.time})
      end
    end)
  end

  def schema, do: %{users: {:array, :string}}

  defp destination(%Dialog{b_key: b_key} = dialog) do
    %{
      dialog: dialog,
      pub_key: Base.encode16(b_key, case: :lower),
      type: :dialog
    }
  end

  defp entry(file_info, me) do
    %{
      client_last_modified: file_info.time,
      client_name: me |> client_name(),
      client_relative_path: nil,
      client_size: file_info.size,
      client_type: "text/plain"
    }
  end

  defp client_name(%Identity{name: name, public_key: pub_key} = _me),
    do: "This is my ID #{name}-#{Enigma.short_hash(pub_key)}.social_part"

  defp save({file_key, share_key}, {file_size, file_secret}) do
    ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end

  defp send(entry, dialog, me, {file_key, file_secret, time}) do
    entry
    |> Messages.File.new(file_key, file_secret, time)
    |> Dialogs.add_new_message(me, dialog)
    |> broadcast(dialog)
  end

  defp broadcast(message, dialog) do
    PubSub.broadcast!(
      Chat.PubSub,
      dialog
      |> Dialogs.key()
      |> then(&"dialog:#{&1}"),
      {:dialog, {:new_dialog_message, message}}
    )
  end
end
