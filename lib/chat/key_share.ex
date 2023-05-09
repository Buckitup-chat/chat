defmodule Chat.KeyShare do
  @moduledoc "Manipulate social sharing keys"

  alias Chat.{Dialogs, Dialogs.Dialog, Identity}
  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Upload.UploadKey

  @threshold 4

  def threshold, do: @threshold

  def generate_key_shares({%Identity{private_key: private_key} = me, users}) do
    amount = Enum.count(users)
    hash = private_key |> Enigma.hash() |> Enigma.sign(private_key)

    me
    |> Identity.to_strings()
    |> Enum.at(1)
    |> Enigma.hide_secret_in_shares(amount, @threshold)
    |> Enum.zip_reduce(users, [], fn key, user, acc ->
      acc ++
        [
          %{
            user: user,
            key: {key, hash} |> encode_content()
          }
        ]
    end)
  end

  def save_shares(shares, {me, time_offset}) do
    shares
    |> Enum.map(fn share ->
      with dialog <- Dialogs.find_or_open(me, share.user),
           file_info <- %{
             size: byte_size(share.key),
             time: Chat.Time.monotonic_to_unix(time_offset)
           },
           entry <- entry(file_info, me),
           destination <- destination(dialog),
           file_key <- UploadKey.new(destination, dialog.b_key, entry),
           file_secret <- ChunkedFiles.new_upload(file_key),
           :ok <- save({file_key, share.key}, {file_info.size, file_secret}) do
        %{
          entry: entry,
          dialog: dialog,
          me: me,
          file_info: {file_key, file_secret, file_info.time},
          size: file_info.size,
          key: share.key
        }
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

  defp encode_content({key, hash}),
    do: Base.encode16(key, case: :lower) <> "\n" <> Base.encode16(hash, case: :lower)
end
