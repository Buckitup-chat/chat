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
  alias Chat.Content.Files
  alias Chat.Messages.ExportHelper
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Layout.Message

  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.HTMLEngine

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

      {room, my_id, me, peer} =
        case type do
          :dialog ->
            {_dialog, _messages_ids, me, peer} = data
            {nil, nil, me, peer}

          :room ->
            {_messages_ids, room, my_id, _room_identity} = data
            {room, my_id, nil, nil}
        end

      messages_stream =
        messages
        |> Stream.map(fn msg ->
          HTMLEngine.component(
            &Message.message_block/1,
            [
              chat_type: type,
              export?: true,
              msg: msg,
              me: me,
              my_id: my_id,
              peer: peer,
              room: room,
              timezone: timezone
            ],
            {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
          )
          |> Safe.to_iodata()
        end)

      exported_messages =
        Stream.concat([
          ["<html><head>"],
          [~S(
            <meta charset="utf-8" />
            <meta http-equiv="X-UA-Compatible" content="IE=edge" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <title>Chat · BuckItUp</title>
          )],
          ["<style>"],
          style_stream,
          ["</style></head><body>"],
          messages_stream,
          ["</body></html>"]
        ])

      index_entry = Zstream.entry("index.html", exported_messages)

      file_entries =
        messages
        |> Enum.reduce([], fn msg, file_entries ->
          with %{type: type, content: json} when type in [:audio, :file, :image, :video] <- msg,
               {id, content} <- StorageId.from_json(json),
               [chunk_key, chunk_secret_raw, _, _type, filename, _size] <- Files.get(id, content),
               chunk_secret <- Base.decode64!(chunk_secret_raw),
               file_stream <- ChunkedFiles.stream_chunks(chunk_key, chunk_secret) do
            filename = ExportHelper.get_filename(filename, id)

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

  defp get_filename(:dialog, {_dialog, _messages_ids, _me, peer}),
    do: "chat_#{Enigma.short_hash(peer)}_messages"

  defp get_filename(:room, {_messages_ids, room, _my_id, _room_identity}),
    do: "room_#{Enigma.short_hash(room)}_messages"

  defp fetch_messages(:dialog, {dialog, messages_ids, me, _peer}) do
    messages_ids
    |> Stream.map(&Dialogs.read_message(dialog, &1, me))
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_messages(:room, {messages_ids, _room, _my_id, room_identity}) do
    messages_ids
    |> Stream.map(fn msg -> Rooms.read_message(msg, room_identity, &User.id_map_builder/1) end)
    |> Enum.reject(&is_nil/1)
  end
end
