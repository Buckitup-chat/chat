defmodule ChatWeb.ZipController do
  @moduledoc """
  Enables downloading multiple messages in an archive.

  The archive includes:
  - index.html file showing all the selected messages
  - files directory containing all the files from the selected messages
  """

  use ChatWeb, :controller

  alias Chat.Rooms.Message
  alias ChatWeb.MainLive.Layout.ExportedMessage
  alias Chat.Broker
  alias Chat.ChunkedFiles
  alias Chat.Dialogs
  alias Chat.Dialogs.PrivateMessage
  alias Chat.Files
  alias Chat.User
  alias Chat.Utils.StorageId

  def get(conn, params) do
    with %{"broker_key" => broker_key} <- params,
         {messages_ids, user_data, user_id, timezone} <- Broker.get(broker_key),
         {identity, _rooms} = User.device_decode(user_data),
         peer <- User.by_id(user_id),
         dialog <- Dialogs.find_or_open(identity, peer),
         {messages, users} when not is_nil(messages) and not is_nil(users) <-
           fetch_messages_and_users_ids(dialog, identity, messages_ids) do
      conn =
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", "attachment; filename=messages.zip")
        |> send_chunked(200)

      style_stream =
        :chat
        |> :code.priv_dir()
        |> Path.join("static/assets/app.css")
        |> File.stream!()

      messages_stream =
        messages
        |> Stream.map(fn message ->
          author =
            case message do
              %PrivateMessage{} ->
                peer

              %Message{} = message ->
                Map.get(users, message.author_hash)
            end

          %{author: author, message: message, timezone: timezone}
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
        |> Enum.reduce([], fn message, file_entries ->
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

    # rescue
    #   _ ->
    #     conn
    #     |> send_resp(404, "")
  end

  defp fetch_messages_and_users_ids(dialog, identity, messages_ids) do
    {messages, users_ids} =
      Enum.map_reduce(messages_ids, MapSet.new(), fn message_id, users_ids ->
        case Dialogs.read_message(dialog, message_id, identity) do
          # %Message{} = message ->
          #   users_ids = MapSet.put(users_ids, message.author_hash)
          #   {message, users_ids}

          %PrivateMessage{} = message ->
            {message, users_ids}

          _ ->
            {nil, users_ids}
        end
      end)

    messages = Enum.reject(messages, &is_nil/1)
    users = User.id_map_builder(users_ids)

    with true <- length(messages) == length(messages_ids),
         true <- map_size(users) == MapSet.size(users_ids) do
      {messages, users}
    else
      _ ->
        {nil, nil}
    end
  end
end
