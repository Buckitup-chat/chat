defmodule Chat.Sync.UsbDriveFileDumper do
  @moduledoc """
  Saves file as a message.
  """

  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret, FileIndex, Identity, Log, Messages, Rooms}
  alias Chat.Db.ChangeTracker
  alias Chat.Sync.UsbDriveDumpFile
  alias Chat.Upload.UploadKey
  alias Phoenix.PubSub

  @chunk_size Application.compile_env(:chat, :file_chunk_size)

  def dump(%UsbDriveDumpFile{} = file, room_key, %Identity{} = room_identity) do
    timestamp =
      file.datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix()

    type =
      file
      |> Map.get(:name)
      |> Path.extname()
      |> String.slice(1..-1)
      |> String.downcase()
      |> MIME.type()

    destination = %{
      pub_key: Base.encode16(room_key, case: :lower),
      type: :room
    }

    entry = %{
      client_last_modified: timestamp,
      client_name: file.name,
      client_relative_path: file.path,
      client_size: file.size,
      client_type: type
    }

    file_key = UploadKey.new(destination, room_key, entry)

    file_secret = ChunkedFiles.new_upload(file_key)
    ChunkedFilesMultisecret.generate(file_key, file.size, file_secret)

    file.path
    |> File.stream!([], @chunk_size)
    |> Stream.with_index()
    |> Enum.each(fn {chunk, index} ->
      chunk_start = @chunk_size * index

      chunk_end =
        if(@chunk_size * (index + 1) < file.size - 1,
          do: @chunk_size * (index + 1),
          else: file.size - 1
        )

      ChunkedFiles.save_upload_chunk(file_key, {chunk_start, chunk_end}, file.size, chunk)
    end)

    {_index, message} =
      msg =
      entry
      |> Messages.File.new(file_key, file_secret, timestamp)
      |> Rooms.add_new_message(room_identity, room_key)

    Rooms.on_saved(msg, room_key, fn ->
      FileIndex.save(file_key, room_key, message.id, file_secret)
      ChangeTracker.await({:file_index, room_key, file_key, message.id})

      topic =
        room_key
        |> Base.encode16(case: :lower)
        |> then(&"room:#{&1}")

      PubSub.broadcast!(Chat.PubSub, topic, {:room, {:new_message, msg}})

      Log.message_room(room_identity, timestamp, room_key)
    end)
  end
end
