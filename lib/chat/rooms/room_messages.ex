defmodule Chat.Rooms.RoomMessages do
  @moduledoc "Room messages logic"

  alias Chat.Content
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.DryStorable
  alias Chat.Identity
  alias Chat.Rooms.Message
  alias Chat.Rooms.PlainMessage
  alias Chat.Rooms.Room

  @db_key :room_message

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

  def on_saved({index, msg}, room_hash, ok_fn) do
    room_hash
    |> key(index, msg.id)
    |> ChangeTracker.promise(ok_fn)
  end

  def await_saved({index, msg}, room_hash) do
    room_hash
    |> key(index, msg.id)
    |> ChangeTracker.await()
  end

  def read(%Room{pub_key: room_key}, identity, {index, id} = _before, amount) do
    {
      key(room_key, 0, 0),
      key(room_key, index, id)
    }
    |> Db.select(amount)
    |> Enum.reverse()
    |> Enum.map(fn {{_, _, index, _}, msg} -> read({index, msg}, identity) end)
    |> Enum.reject(&is_nil/1)
  end

  def read(
        {index,
         %Message{
           timestamp: timestamp,
           type: type,
           author_key: author_key,
           id: id,
           encrypted: encrypted
         }},
        identity
      ) do
    with {:ok, content} <-
           encrypted |> Enigma.decrypt_signed(identity.private_key, author_key, author_key) do
      %PlainMessage{
        timestamp: timestamp,
        type: type,
        author_key: author_key,
        index: index,
        id: id,
        content: content
      }
    else
      _ -> nil
    end
  end

  def read({index, id} = _msg_id, identity) do
    identity
    |> Identity.pub_key()
    |> key(index, id)
    |> Db.get()
    |> then(&read({index, &1}, identity))
  end

  def get_next_message({index, id} = _msg_id, room_identity, predicate) do
    with room_key <- Identity.pub_key(room_identity),
         msg_key <- key(room_key, index, id),
         msg_key_max <- key(room_key, nil, "some") do
      Db.get_next(
        msg_key,
        msg_key_max,
        predicate
      )
    end
  end

  def get_prev_message({index, id} = _msg_id, room_identity, predicate) do
    with room_key <- Identity.pub_key(room_identity),
         msg_key <- key(room_key, index, id),
         msg_key_min <- key(room_key, 0, 0) do
      Db.get_prev(
        msg_key,
        msg_key_min,
        predicate
      )
    end
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
         true <- msg.author_key == author.public_key do
      {index, msg}
      |> read(room_identity)
      |> Content.delete([room_key], msg.id)

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
         true <- msg.author_key == author.public_key do
      {index, msg}
      |> read(room_identity)
      |> Content.delete([room_key], msg.id)

      Db.delete(msg_key)
    end
  end

  def key(room_key, time, 0),
    do: {@db_key, room_key, time, 0}

  def key(room_key, time, id),
    do: {@db_key, room_key, time, id |> Enigma.hash()}

  def delete_by_room(room_key) do
    {
      {@db_key, room_key, -1, 0},
      {@db_key, room_key, nil, 0}
    }
    |> Db.bulk_delete()
  end

  defp add_message(content, room_key, author, opts) do
    content
    |> Enigma.encrypt_and_sign(author.private_key, room_key)
    |> Message.new(author.public_key, opts)
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
