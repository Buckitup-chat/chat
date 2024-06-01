defmodule Chat do
  @moduledoc """
  High level functions
  """
  alias Chat.FileIndex
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Identity
  alias Chat.ChunkedFiles

  def file_message_from_text_to_my_notes(content, name, mime_type, %Identity{} = me) do
    file_key = UUID.uuid4() |> Enigma.hash()
    file_secret = ChunkedFiles.new_upload(file_key)
    file_size = byte_size(content)

    :ok = ChunkedFiles.save_upload_chunk(file_key, {0, max(0, file_size - 1)}, file_size, content)

    now = DateTime.utc_now() |> DateTime.to_unix()
    dialog = Chat.Dialogs.find_or_open(me)

    %{
      client_size: file_size,
      client_type: mime_type,
      client_name: name
    }
    |> Messages.File.new(file_key, file_secret, now)
    |> Dialogs.add_new_message(me, dialog)
    |> tap(fn {_index, msg} ->
      FileIndex.save(file_key, dialog.a_key, msg.id, true)
    end)
  end

  alias Chat.Db.Copying

  def db_get(key) do
    case key do
      {:file_chunk, file_key, first, last} -> read_chunk({first, last}, file_key)
      _ -> Chat.Db.get(key)
    end
  end

  def db_put(key, value) do
    Chat.Db.put(key, value)
    Copying.await_written_into([key], Chat.Db.db())
  end

  def db_has?(key) do
    case key do
      {:file_chunk, key, first, last} -> Chat.FileFs.has_file?({key, first, last})
      key -> Chat.Db.has_key?(key)
    end
  end

  defp read_chunk(range, key) do
    {data, _last} =
      Chat.FileFs.read_exact_file_chunk(range, key, path())

    data
  end

  defp path, do: CubDB.data_dir(Chat.Db.db()) <> "_files"
end
