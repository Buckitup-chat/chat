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
    |> add_message(room_key, author, opts |> Keyword.merge(type: :text))
  end

  def add_request_message(%Room{pub_key: room_key}, author, opts),
    do: add_request_message(room_key, author, opts)

  def add_request_message(room_key, author, opts),
    do: add_message("", room_key, author, opts |> Keyword.merge(type: :request))

  def add_memo(%Room{pub_key: room_key}, author, text, opts),
    do: add_memo(room_key, author, text, opts)

  def add_memo(room_key, author, text, opts),
    do: add_stored(room_key, author, text, &Memo.add/1, opts |> Keyword.merge(type: :memo))

  def add_file(%Room{pub_key: room_key}, author, data, opts),
    do: add_file(room_key, author, data, opts)

  def add_file(room, author, data, opts),
    do: add_stored(room, author, data, &Files.add/1, opts |> Keyword.merge(type: :file))

  def add_image(%Room{pub_key: room_key}, author, data, opts),
    do: add_image(room_key, author, data, opts)

  def add_image(room, author, data, opts),
    do: add_stored(room, author, data, &Images.add/1, opts |> Keyword.merge(type: :image))

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

  def read({time, id} = _msg_id, identity, pub_keys_mapper) do
    identity
    |> Identity.pub_key()
    |> key(time, id)
    |> Db.get()
    |> then(&[&1])
    |> filter_signed(pub_keys_mapper)
    |> Enum.map(&read(&1, identity))
    |> List.first()
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

  def update_message(
        {time, id} = _msg_id,
        %Identity{} = room_identity,
        %Identity{} = author,
        new_text
      ) do
    with room_key <- room_identity |> Identity.pub_key(),
         msg_key <- room_key |> key(time, id),
         msg <- Db.get(msg_key),
         true <- msg.author_hash == author |> Utils.hash() do
      msg
      |> read(room_identity)
      |> Content.delete()

      case new_text do
        {:memo, text} ->
          add_memo(room_key, author, text, now: msg.timestamp, id: msg.id)

        text ->
          add_message(text, room_key, author, now: msg.timestamp, id: msg.id)
      end
    end
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

  def delete_by_room(hash) do
    {
      {@db_key, hash |> Utils.binhash(), -1, 0},
      {@db_key, hash |> Utils.binhash(), nil, 0}
    }
    |> Db.bulk_delete()
  end

  defp db_save(message, room_key) do
    room_key
    |> key(message.timestamp, message.id)
    |> Db.put(message)
  end

  defp add_stored(
         room_key,
         %Identity{} = author,
         data,
         store_adding_fun,
         opts
       ) do
    data
    |> then(store_adding_fun)
    |> StorageId.to_json()
    |> add_message(room_key, author, opts)
  end

  defp add_message(content, room_key, author, opts) do
    content
    |> Utils.encrypt_and_sign(room_key, author)
    |> Message.new(author |> Utils.hash(), opts)
    |> tap(&db_save(&1, room_key))
  end
end
