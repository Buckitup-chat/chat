defmodule Chat.Rooms.RoomMessages do
  @moduledoc "Room messages logic"

  alias Chat.Content
  alias Chat.Db
  alias Chat.Files
  alias Chat.Identity
  alias Chat.Images
  alias Chat.Memo
  alias Chat.Rooms.Message
  alias Chat.Rooms.PlainMessage
  alias Chat.Rooms.Room
  alias Chat.Utils
  alias Chat.Utils.StorageId

  @db_key :room_message

  def add_text(
        %Room{pub_key: room_key},
        %Identity{} = author,
        text,
        opts
      ) do
    text
    |> Utils.encrypt_and_sign(room_key, author)
    |> Message.new(author |> Utils.hash(), opts |> Keyword.merge(type: :text))
    |> tap(&db_save(&1, room_key))
  end

  def add_memo(room, author, text),
    do: add_stored(room, author, text, {:memo, &Memo.add/1})

  def add_file(room, author, data),
    do: add_stored(room, author, data, {:file, &Files.add/1})

  def add_image(room, author, data),
    do: add_stored(room, author, data, {:image, &Images.add/1})

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

  def delete_message(
        {time, id},
        %Identity{} = room_identity,
        %Identity{} = author
      ) do
    with room_key <- room_identity |> Identity.pub_key(),
         msg_key <- room_key |> key(time, id),
         msg <- Db.get(msg_key),
         true <- msg.author_hash == author |> Utils.hash() do
      msg
      |> read(room_identity)
      |> Content.delete()

      Db.delete(msg_key)
    end
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

  defp db_save(message, room_key) do
    room_key
    |> key(message.timestamp, message.id)
    |> Db.put(message)
  end

  defp add_stored(
         %Room{pub_key: room_key},
         %Identity{} = author,
         data,
         {type, store_adding_fun}
       ) do
    data
    |> then(store_adding_fun)
    |> StorageId.to_json()
    |> Utils.encrypt_and_sign(room_key, author)
    |> Message.new(author |> Utils.hash(), type: type)
    |> tap(&db_save(&1, room_key))
  end
end
