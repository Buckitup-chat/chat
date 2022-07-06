defmodule Chat.Dialogs.Dialog do
  @moduledoc "Module to hold a conversation between A and B"

  alias Chat.Db
  alias Chat.Dialogs.Message
  alias Chat.Dialogs.PrivateMessage
  alias Chat.DryStorable
  alias Chat.Files
  alias Chat.Images
  alias Chat.Memo
  alias Chat.Ordering
  alias Chat.RoomInvites

  alias Chat.Card
  alias Chat.Content
  alias Chat.Identity
  alias Chat.Utils
  alias Chat.Utils.StorageId

  @derive {Inspect, only: []}
  defstruct [:a_key, :b_key]

  @db_prefix :dialog_message

  def start(%Identity{} = a, %Card{pub_key: b_key}) do
    %__MODULE__{
      a_key: a |> Identity.pub_key(),
      b_key: b_key
    }
  end

  def add_file(
        %__MODULE__{} = dialog,
        %Chat.Identity{} = source,
        data,
        now
      ) do
    data
    |> Files.add()
    |> StorageId.to_json()
    |> add_message(dialog, source, now: now, type: :file)
  end

  def add_image(
        %__MODULE__{} = dialog,
        %Chat.Identity{} = source,
        data,
        now
      ) do
    data
    |> Images.add()
    |> StorageId.to_json()
    |> add_message(dialog, source, now: now, type: :image)
  end

  def add_room_invite(
        %__MODULE__{} = dialog,
        %Chat.Identity{} = source,
        %Identity{} = room_identity,
        now
      ) do
    room_identity
    |> Identity.to_strings()
    |> RoomInvites.add()
    |> StorageId.to_json()
    |> add_message(dialog, source, now: now, type: :room_invite)
  end

  def add_new_message(
        message,
        %Identity{} = source,
        %__MODULE__{} = dialog
      ) do
    type = message |> DryStorable.type()
    now = message |> DryStorable.timestamp()

    message
    |> DryStorable.content()
    |> add_message(dialog, source, now: now, type: type)
  end

  def read(%Message{} = msg, index, identitiy, side, peer_key) when side in [:a_copy, :b_copy] do
    is_mine? = (side == :a_copy and msg.is_a_to_b?) or (side == :b_copy and !msg.is_a_to_b?)

    %PrivateMessage{
      timestamp: msg.timestamp,
      type: msg.type,
      index: index,
      id: msg.id,
      is_mine?: is_mine?,
      content:
        msg[side]
        |> Utils.decrypt_signed(identitiy, (is_mine? && Identity.pub_key(identitiy)) || peer_key)
    }
  end

  def read(
        %__MODULE__{} = dialog,
        %Identity{} = me,
        before,
        amount
      ) do
    side = dialog |> my_side(me)

    dialog
    |> get_messages(before, amount)
    |> Enum.map(fn {{_, _, index, _}, message} ->
      read(message, index, me, side, peer_key(dialog, side))
    end)
    |> Enum.reverse()
  end

  def get_message(%__MODULE__{} = dialog, {time, id}) do
    msg_key(dialog, time, id)
    |> Db.get()
  end

  def my_side(%__MODULE__{a_key: a_key, b_key: b_key}, identitiy) do
    case identitiy |> Identity.pub_key() do
      ^a_key -> :a_copy
      ^b_key -> :b_copy
      _ -> raise "unknown_user_in_dialog"
    end
  end

  def peer_key(%__MODULE__{a_key: key}, :b_copy), do: key
  def peer_key(%__MODULE__{b_key: key}, :a_copy), do: key

  def is_mine?(dialog, %{is_a_to_b?: is_a_to_b}, me) do
    dialog
    |> my_side(me)
    |> then(fn
      :a_copy -> is_a_to_b
      :b_copy -> !is_a_to_b
    end)
  end

  def delete(%__MODULE__{} = dialog, %Identity{} = author, msg_id) do
    fn msg, index, key ->
      side = my_side(dialog, author)

      msg
      |> read(index, author, side, peer_key(dialog, side))
      |> Content.delete()

      Db.delete(key)
      :ok
    end
    |> change_my_message(author, dialog, msg_id)
  end

  def update(%__MODULE__{} = dialog, %Identity{} = author, msg_id, new_text) do
    fn msg, index, _key ->
      side = my_side(dialog, author)

      msg
      |> read(index, author, side, peer_key(dialog, side))
      |> Content.delete()

      {type, content} =
        case new_text do
          {:memo, text} ->
            text
            |> Memo.add()
            |> StorageId.to_json()
            |> then(&{:memo, &1})

          text ->
            {:text, text}
        end

      content
      |> add_message(dialog, author, type: type, now: msg.timestamp, id: msg.id, index: index)
    end
    |> change_my_message(author, dialog, msg_id)
  end

  def msg_key(%__MODULE__{} = dialog, time, 0),
    do: {@db_prefix, dialog |> dialog_key(), time, 0}

  def msg_key(%__MODULE__{} = dialog, time, id),
    do: {@db_prefix, dialog |> dialog_key(), time, id |> Utils.binhash()}

  def dialog_key(%__MODULE__{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> Enum.map(&Utils.hash/1)
    |> Enum.sort()
    |> Enum.join()
    |> Utils.hash()
    |> Utils.binhash()
  end

  defp change_my_message(action_fn, author, dialog, {index, id}) do
    key = dialog |> msg_key(index, id)
    msg = Db.get(key)

    case dialog |> is_mine?(msg, author) do
      true -> action_fn.(msg, index, key)
      _ -> nil
    end
  end

  defp add_message(
         content,
         %__MODULE__{a_key: a_key, b_key: a_key} = dialog,
         %Identity{} = source,
         opts
       ) do
    a_copy = content |> Utils.encrypt_and_sign(a_key, source)

    Message.a_to_b(a_copy, a_copy, opts)
    |> tap(&store_message(&1, dialog, opts[:index]))
  end

  defp add_message(
         content,
         %__MODULE__{a_key: a_key, b_key: b_key} = dialog,
         %Identity{} = source,
         opts
       ) do
    a_copy = content |> Utils.encrypt_and_sign(a_key, source)
    b_copy = content |> Utils.encrypt_and_sign(b_key, source)

    dialog
    |> my_side(source)
    |> case do
      :a_copy -> Message.a_to_b(a_copy, b_copy, opts)
      :b_copy -> Message.b_to_a(a_copy, b_copy, opts)
    end
    |> tap(&store_message(&1, dialog, opts[:index]))
  end

  defp store_message(%{id: id} = msg, dialog, index) do
    next = index || Ordering.next({@db_prefix, dialog |> dialog_key()})

    dialog
    |> msg_key(next, id)
    |> Db.put(msg)
  end

  defp get_messages(dialog, {max_index, id}, amount) do
    {
      msg_key(dialog, 0, 0),
      msg_key(dialog, max_index, id)
    }
    |> Db.select(amount)
  end
end
