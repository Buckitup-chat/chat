defmodule Chat.KeyShare do
  @moduledoc "Manipulate social sharing keys"

  alias Chat.{Dialogs, Dialogs.Dialog, Identity}
  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Upload.UploadKey

  @threshold 4

  def threshold, do: @threshold

  def generate_key_shares({%Identity{private_key: private_key} = _me, users}) do
    shares =
      private_key
      |> Enigma.hide_secret_in_shares(users |> Enum.count(), @threshold)

    share_count = Enum.count(shares)

    for i <- 0..(share_count - 1), into: [] do
      %{
        user: Enum.at(users, i),
        key: Enum.at(shares, i) |> Base.encode64()
      }
    end
  end

  def save_shares(shares, {me, time_offset}) do
    shares
    |> Enum.reduce([], fn share, acc ->
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

        acc ++
          [
            %{
              entry: entry,
              dialog: dialog,
              me: me,
              file_info: {file_key, file_secret, file_info.time}
            }
          ]
      end
    end)
  end

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
end
