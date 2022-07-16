defmodule Chat.Rooms.RoomMessages do
  @moduledoc "Room messages logic"

  alias Chat.Content
  alias Chat.Db
  alias Chat.DryStorable
  alias Chat.Identity
  alias Chat.Rooms.Message
  alias Chat.Rooms.PlainMessage
  alias Chat.Rooms.Room
  alias Chat.Utils

  @db_key :room_message

  @spec add_new_message(any(), Identity.t(), Dialog.t()) ::
          {index :: integer(), Message.t()}
  def add_new_message(
        message,
        %Identity{} = author,
        room_key,
        opts \\ []
      ) do
    type = message |> DryStorable.type()
    now = message |> DryStorable.timestamp()

    message
    |> DryStorable.content()
    |> add_message(room_key, author, opts |> Keyword.merge(type: type, now: now))
  end

  def read(%Room{pub_key: room_key}, identity, pub_keys_mapper, {time, id} = _before, amount) do
    {
      key(room_key, 0, 0),
      key(room_key, time, id)
    }
    |> Db.select(amount)
    |> Enum.reverse()
    |> filter_signed(pub_keys_mapper)
    |> Enum.map(fn {{_, _, index, _}, msg} -> read({index, msg}, identity) end)
  end

  def read({index, id} = _msg_id, identity, pub_keys_mapper) do
    identity
    |> Identity.pub_key()
    |> key(index, id)
    |> Db.get()
    |> then(&[{{nil, nil, index, nil}, &1}])
    |> filter_signed(pub_keys_mapper)
    |> Enum.map(fn {{_, _, index, _}, msg} -> read({index, msg}, identity) end)
    |> List.first()
  end

  def read(
        {index,
         %Message{
           timestamp: timestamp,
           type: type,
           author_hash: author_hash,
           id: id,
           encrypted: {encrypted, _}
         }},
        identity
      ) do
    %PlainMessage{
      timestamp: timestamp,
      type: type,
      author_hash: author_hash,
      index: index,
      id: id,
      content: encrypted |> Utils.decrypt(identity)
    }
  end

  def update_message(
        new_message,
        {index, id} = _msg_id,
        %Identity{} = author,
        %Identity{} = room_identity
      ) do
    with room_key <- room_identity |> Identity.pub_key(),
         msg_key <- room_key |> key(index, id),
         msg <- Db.get(msg_key),
         true <- msg.author_hash == author |> Utils.hash() do
      {index, msg}
      |> read(room_identity)
      |> Content.delete()

      type = DryStorable.type(new_message)

      new_message
      |> DryStorable.content()
      |> add_message(room_key, author, type: type, now: msg.timestamp, id: msg.id, index: index)
    end
  end

  def delete_message(
        {index, id},
        %Identity{} = room_identity,
        %Identity{} = author
      ) do
    with room_key <- room_identity |> Identity.pub_key(),
         msg_key <- room_key |> key(index, id),
         msg <- Db.get(msg_key),
         true <- msg.author_hash == author |> Utils.hash() do
      {index, msg}
      |> read(room_identity)
      |> Content.delete()

      Db.delete(msg_key)
    end
  end

  def filter_signed(messages, pub_keys_mapper) do
    ids =
      messages
      |> Enum.map(fn {_, %Message{author_hash: id}} -> id end)
      |> Enum.uniq()

    map = ids |> then(pub_keys_mapper)

    messages
    |> Enum.filter(fn {_, %Message{encrypted: {data, sign}, author_hash: author}} ->
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

  defp add_message(content, room_key, author, opts) do
    content
    |> Utils.encrypt_and_sign(room_key, author)
    |> Message.new(author |> Utils.hash(), opts)
    |> db_save(room_key, opts[:index])
  end

  defp db_save(message, room_key, index) do
    next = index || Chat.Ordering.next({@db_key, room_key})

    room_key
    |> key(next, message.id)
    |> Db.put(message)

    {next, message}
  end
end
