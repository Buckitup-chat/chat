defmodule ChatWeb.ZipController do
  @moduledoc """
  Enables downloading multiple messages in an archive.

  The archive includes:
  - index.html file showing all the selected messages
  - files directory containing all the files from the selected messages
  """

  use ChatWeb, :controller

  alias Chat.Broker
  alias Chat.ChunkedFiles
  alias Chat.Dialogs
  alias Chat.Files
  alias Chat.Rooms
  alias Chat.Rooms.PlainMessage
  alias Chat.User
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Layout.ExportedMessage

  def get(conn, params) do
    with %{"broker_key" => broker_key} <- params,
         {type, data, timezone} <- Broker.get(broker_key) do
      filename = get_filename(type, data)

      conn =
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", "attachment; filename=#{filename}.zip")
        |> send_chunked(200)

      style_stream =
        :chat
        |> :code.priv_dir()
        |> Path.join("static/assets/app.css")
        |> File.stream!()

      messages = fetch_messages(type, data)

      room =
        if type == :room do
          {_messages_ids, room, _room_identity} = data
          room
        end

      messages_stream =
        messages
        |> Stream.map(fn {message, author} ->
          %{author: author, message: message, room: room, timezone: timezone}
          |> ExportedMessage.message_block()
          |> Phoenix.HTML.Safe.to_iodata()
        end)

      exported_messages =
        Stream.concat([
          ["<html><head>"],
          ["<style>"],
          style_stream,
          ["</style></head><body>"],
          messages_stream,
          ["</body></html>"]
        ])

      index_entry = Zstream.entry("index.html", exported_messages)

      file_entries =
        messages
        |> Enum.reduce([], fn {message, _author}, file_entries ->
          with %{type: type, content: json} when type in [:file, :image, :video] <- message,
               {id, content} <- StorageId.from_json(json),
               [chunk_key, chunk_secret_raw, _, _type, filename, _size] <- Files.get(id, content),
               chunk_secret <- Base.decode64!(chunk_secret_raw),
               file_stream <- ChunkedFiles.stream_chunks(chunk_key, chunk_secret) do
            {extension, filename} =
              filename
              |> String.split(".")
              |> List.pop_at(-1)

            filename = Enum.join(filename, ".") <> "_" <> id <> "." <> extension

            entry = Zstream.entry("files/#{filename}", file_stream)

            [entry | file_entries]
          else
            _ ->
              file_entries
          end
        end)
        |> Enum.reject(&is_nil/1)

      [index_entry | file_entries]
      |> Zstream.zip()
      |> Enum.reduce_while(conn, fn archive, conn ->
        case chunk(conn, archive) do
          {:ok, conn} ->
            {:cont, conn}

          {:error, :closed} ->
            {:halt, conn}
        end
      end)
    else
      _ ->
        raise "404"
    end
  rescue
    _ ->
      send_resp(conn, 404, "")
  end

  defp get_filename(:dialog, {_messages_ids, peer, _user_data}),
    do: "chat_#{short_hash(peer.hash)}_messages"

  defp get_filename(:room, {_messages_ids, room, _room_identity}),
    do: "room_#{short_hash(room.admin_hash)}_messages"

  def short_hash(hash), do: hash |> String.split_at(-6) |> elem(1)

  defp fetch_messages(:dialog, {messages_ids, peer, user_data}) do
    {identity, _rooms} = User.device_decode(user_data)
    dialog = Dialogs.find_or_open(identity, peer)

    messages_ids
    |> Stream.map(&{Dialogs.read_message(dialog, &1, identity), peer})
    |> Enum.reject(&is_nil(elem(&1, 0)))
  end

  defp fetch_messages(:room, {messages_ids, _room, room_identity}) do
    messages_ids
    |> Stream.map(fn message_id ->
      case Rooms.read_message(message_id, room_identity, &User.id_map_builder/1) do
        %PlainMessage{} = message ->
          author = User.by_id(message.author_hash)
          {message, author}

        nil ->
          {nil, nil}
      end
    end)
    |> Enum.reject(&is_nil(elem(&1, 0)))
  end
end