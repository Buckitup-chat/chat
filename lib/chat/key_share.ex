defmodule Chat.KeyShare do
  @moduledoc "Manipulate social sharing keys"

  alias Chat.Identity
  alias Chat.{Actor, ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Upload.UploadKey
  alias Chat.{Dialogs, Dialogs.Dialog, Messages}

  alias ChatWeb.MainLive.Page

  def generate_key_shares({me, rooms, users}) do
    share_count = Enum.count(users)
    base_key = Actor.new(me, rooms, %{}) |> Actor.to_encrypted_json("") |> Base.encode64()
    len_part = ceil(String.length(base_key) / share_count)

    for i <- 0..(share_count - 1), into: [] do
      start_idx = i * len_part
      end_idx = start_idx + len_part - 1

      %{
        user: Enum.at(users, i),
        key: String.slice(base_key, start_idx..end_idx)
      }
    end
  end

  def send_shares(shares, {me, time_offset}) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    shares
    |> Enum.each(fn share ->
      with dialog <- Dialogs.find_or_open(me, share.user),
           file_path <- file_path(me),
           file_info <- generate_file(file_path, share.key),
           entry <- entry(file_info, {me, file_path}),
           destination <- destination(dialog),
           file_key <- UploadKey.new(destination, dialog.b_key, entry),
           file_secret <- ChunkedFiles.new_upload(file_key) do
        save({file_key, share.key}, {file_info.size, file_secret})
        send(entry, dialog, me, {file_key, file_secret, time})
        File.rm!(file_path)
      end
    end)
  end

  defp file_path(%Identity{name: name} = me),
    do: "/tmp/#{name}-#{Enigma.short_hash(me)}.social_part"

  defp generate_file(path, key) do
    File.write!(path, key)
    File.stat!(path)
  end

  defp destination(%Dialog{b_key: b_key} = dialog) do
    %{
      dialog: dialog,
      pub_key: Base.encode16(b_key, case: :lower),
      type: :dialog
    }
  end

  defp entry(file_info, {me, path}) do
    %{
      client_last_modified:
        file_info.mtime |> Timex.format("{YYYY}-{M}-{D} {h24}:{m}:{s}") |> elem(1),
      client_name: "#{me.name}-#{Enigma.short_hash(me)}.social_part",
      client_relative_path: path,
      client_size: file_info.size,
      client_type: "text/plain"
    }
  end

  defp save({file_key, share_key}, {file_size, file_secret}) do
    ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end

  defp send(entry, dialog, me, {file_key, file_secret, time}) do
    message =
      entry
      |> Messages.File.new(file_key, file_secret, time)
      |> Dialogs.add_new_message(me, dialog)

    Page.Dialog.broadcast_new_message(message, dialog, me, time)
  end

  def schema, do: %{users: {:array, :string}}
end
