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
    encrypted = Utils.encrypt_and_sign(text, room_key, author)
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
    encrypted = Utils.encrypt_and_sign(msg, room_key, author)
    message = Message.new(author_hash, encrypted, type: :image)

    room_key
    |> now_key(message.id)
    |> Db.put(message)

    message
  end

  def read(%Room{pub_key: room_key}, identity, pub_keys_mapper, {time, id} = _before, amount) do
    {
      key(room_key, 0, 0),
      key(room_key, time, id)
    }
    |> Db.values(amount)
    |> Enum.reverse()
    |> filter_signed(pub_keys_mapper)
    |> Enum.map(&read(&1, identity))
  end

  def read(
        %Message{
          timestamp: timestamp,
          type: type,
          author_hash: author_hash,
          id: id,
          encrypted: {encrypted, _}
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

  def filter_signed(messages, pub_keys_mapper) do
    ids =
      messages
      |> Enum.map(fn %Message{author_hash: id} -> id end)
      |> Enum.uniq()

    map = ids |> then(pub_keys_mapper)

    messages
    |> Enum.filter(fn %Message{encrypted: {data, sign}, author_hash: author} ->
      Utils.is_signed_by?(sign, data, map |> Map.get(author))
    end)
  end

  def key(room_key, time, 0),
    do: {@db_key, room_key |> Utils.binhash(), time, 0}

  def key(room_key, time, id),
    do: {@db_key, room_key |> Utils.binhash(), time, id |> Utils.binhash()}

  def now_key(room_key, id) do
    key(room_key, System.system_time(:second), id)
  end
end
