defmodule Chat.Sync.UsbDriveFileDumper do
  @moduledoc """
  Saves file as a message.
  """

  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret, FileIndex, Identity, Log, Messages, Rooms}
  alias Chat.Db.ChangeTracker
  alias Chat.Sync.{UsbDriveDumpFile, UsbDriveDumpRoom}
  alias Chat.Upload.{Upload, UploadIndex, UploadKey}
  alias Phoenix.PubSub

  @chunk_size Application.compile_env(:chat, :file_chunk_size)

  def dump(
        %UsbDriveDumpFile{} = file,
        file_number,
        room_key,
        %Identity{} = room_identity,
        monotonic_offset
      ) do
    timestamp =
      file.datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix()

    type =
      file
      |> Map.get(:name)
      |> Path.extname()
      |> String.slice(1..-1//1)
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

    {secret, encrypted_secret} =
      case FileIndex.get(room_key, file_key) do
        nil ->
          maybe_resume_stopped_dump(file_key, file, file_number, room_identity, monotonic_offset)

        encrypted_secret ->
          UsbDriveDumpRoom.update_progress(file_number, file.name, file.size)
          secret = ChunkedFiles.decrypt_secret(encrypted_secret, room_identity)
          {secret, encrypted_secret}
      end

    create_message(room_key, room_identity, file_key, secret, encrypted_secret, entry)
  end

  defp maybe_resume_stopped_dump(file_key, file, file_number, room_identity, monotonic_offset) do
    {next_chunk, secret, encrypted_secret} =
      case UploadIndex.get(file_key) do
        nil ->
          secret = ChunkedFiles.new_upload(file_key)
          encrypted_secret = ChunkedFiles.encrypt_secret(secret, room_identity)
          ChunkedFilesMultisecret.generate(file_key, file.size, secret)
          add_dump_to_index(file_key, secret, room_identity, monotonic_offset)
          {0, secret, encrypted_secret}

        %Upload{} = upload ->
          UploadIndex.delete(file_key)
          secret = ChunkedFiles.decrypt_secret(upload.encrypted_secret, room_identity)
          add_dump_to_index(file_key, secret, room_identity, monotonic_offset)
          next_chunk = ChunkedFiles.next_chunk(file_key)
          {next_chunk, secret, upload.encrypted_secret}
      end

    copy_file(file_key, file, file_number, next_chunk)
    UploadIndex.delete(file_key)

    {secret, encrypted_secret}
  end

  defp add_dump_to_index(key, secret, room_identity, monotonic_offset) do
    encrypted_secret = ChunkedFiles.encrypt_secret(secret, room_identity)
    timestamp = Chat.Time.monotonic_to_unix(monotonic_offset)
    upload = %Upload{encrypted_secret: encrypted_secret, timestamp: timestamp}
    UploadIndex.add(key, upload)
  end

  defp copy_file(file_key, file, file_number, next_chunk) do
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

      if index >= next_chunk do
        ChunkedFiles.save_upload_chunk(file_key, {chunk_start, chunk_end}, file.size, chunk)
      end

      UsbDriveDumpRoom.update_progress(file_number, file.name, chunk_end - chunk_start + 1)
    end)
  end

  defp create_message(room_key, room_identity, file_key, secret, encrypted_secret, entry) do
    {_index, message} =
      msg =
      entry
      |> Messages.File.new(file_key, secret, entry.client_last_modified)
      |> Rooms.add_new_message(room_identity, room_identity)

    Rooms.on_saved(msg, room_key, fn ->
      ChangeTracker.ensure(
        action: fn ->
          FileIndex.save(file_key, room_key, message.id, encrypted_secret)
        end,
        writes_key: {:file_index, room_key, file_key, message.id}
      )

      topic =
        room_key
        |> Base.encode16(case: :lower)
        |> then(&"room:#{&1}")

      PubSub.broadcast!(Chat.PubSub, topic, {:room, {:new_message, msg}})

      Log.message_room(room_identity, entry.client_last_modified, room_key)
    end)
  end
end
