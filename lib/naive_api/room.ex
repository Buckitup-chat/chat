defmodule NaiveApi.Room do
  @moduledoc "Room resolvers"
  use NaiveApi, :resolver
  alias Chat.Card
  alias Chat.ChunkedFiles
  alias Chat.Identity
  alias Chat.MemoIndex
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.Upload.{Upload, UploadIndex}

  @default_amount 20

  def read(_, %{room_keypair: room_keypair} = params, _) do
    room_identity = Identity.from_keys(room_keypair)
    room = room_identity |> Identity.pub_key() |> Rooms.get()

    before_timestamp = params[:before]
    amount = params[:amount] || @default_amount

    room
    |> Rooms.read(room_identity, {before_timestamp, 0}, amount)
    |> Enum.map(fn %{author_key: key} = message ->
      Map.put(message, :author, Card.new("", key))
    end)
    |> ok()
  end

  def send_text(_, %{room_keypair: room_keypair, my_keypair: my_keypair, text: text} = params, _) do
    room_identity = Identity.from_keys(room_keypair)
    me = Identity.from_keys(my_keypair)
    room = room_identity |> Identity.pub_key() |> Rooms.get()

    case String.trim(text) do
      "" ->
        ["Can't write empty text"] |> error()

      content ->
        timestamp = make_sure_timestamp_exists(params[:timestamp])

        {index, %{id: id}} =
          content
          |> Messages.Text.new(timestamp)
          |> Rooms.add_new_message(me, room.pub_key)
          |> MemoIndex.add(room, room.pub_key)

        %{id: id, index: index}
        |> ok()
    end
  end

  def send_file(
        _,
        %{room_keypair: room_keypair, my_keypair: my_keypair, upload_key: upload_key},
        _
      ) do
    room_identity = Identity.from_keys(room_keypair)
    me = Identity.from_keys(my_keypair)
    room = room_identity |> Identity.pub_key() |> Rooms.get()

    case UploadIndex.get(upload_key) do
      nil ->
        ["Wrong upload key"] |> error()

      %Upload{} = upload ->
        {index, %{id: id}} =
          Messages.File.new(
            upload,
            upload_key,
            ChunkedFiles.decrypt_secret(upload.encrypted_secret, me),
            now()
          )
          |> Rooms.add_new_message(me, room.pub_key)

        %{id: id, index: index}
        |> ok()
    end
  end

  defp make_sure_timestamp_exists(nil), do: now()
  defp make_sure_timestamp_exists(time), do: time
  defp now, do: DateTime.utc_now() |> DateTime.to_unix()
end
