defmodule Chat.Rooms.RoomMessages do
  @moduledoc "Room messages logic"

  alias Chat.Db
  alias Chat.Identity
  alias Chat.Images
  alias Chat.Rooms.Message
  alias Chat.Rooms.PlainMessage
  alias Chat.Rooms.Room
  alias Chat.Utils

  @db_key :room_message

  def add_text(
        %Room{pub_key: room_key},
        %Identity{} = author,
        text
      ) do
    author_hash = author |> Identity.pub_key() |> Utils.hash()
    encrypted = Utils.encrypt(text, room_key)
    message = Message.new(author_hash, encrypted, type: :text)

    room_key
    |> now_key(message.id)
    |> Db.put(message)

    message
  end

  def add_image(
        %Room{pub_key: room_key},
        %Identity{} = author,
        data
      ) do
    {key, secret} = Images.add(data)

    msg =
      %{key => secret |> Base.url_encode64()}
      |> Jason.encode!()

    author_hash = author |> Identity.pub_key() |> Utils.hash()
    encrypted = Utils.encrypt(msg, room_key)
    message = Message.new(author_hash, encrypted, type: :image)

    room_key
    |> now_key(message.id)
    |> Db.put(message)

    message
  end

  def read(%Room{pub_key: room_key}, identity, {time, id} = _before, amount) do
    {:ok, list} =
      Db.db()
      |> CubDB.select(
        min_key: key(room_key, 0, 0),
        max_key: key(room_key, time, id),
        max_key_inclusive: false,
        reverse: true,
        pipe: [take: amount]
      )

    list
    |> Enum.map(fn {_k, v} -> read(v, identity) end)
  end

  def read(
        %Message{
          timestamp: timestamp,
          type: type,
          author_hash: author_hash,
          id: id,
          encrypted: encrypted
        },
        identity
      ) do
    %PlainMessage{
      timestamp: timestamp,
      type: type,
      author_hash: author_hash,
      id: id,
      content: encrypted |> Utils.decrypt(identity)
    }
  end

  def key(room_key, time, 0),
    do: {@db_key, room_key |> Utils.binhash(), time, 0}

  def key(room_key, time, id),
    do: {@db_key, room_key |> Utils.binhash(), time, id |> Utils.binhash()}

  def now_key(room_key, id) do
    key(room_key, System.system_time(:second), id)
  end
end
