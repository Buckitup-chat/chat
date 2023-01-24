defmodule Chat.Dialogs.DialogMessaging do
  @moduledoc "Message reading and writing"

  require Logger

  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Message
  alias Chat.Dialogs.PrivateMessage
  alias Chat.DryStorable
  alias Chat.Ordering

  alias Chat.Content
  alias Chat.Identity
  alias Chat.Utils

  @db_prefix :dialog_message

  def add_new_message(
        message,
        %Identity{} = source,
        %Dialog{} = dialog
      ) do
    type = message |> DryStorable.type()
    now = message |> DryStorable.timestamp()

    message
    |> DryStorable.content()
    |> add_message(dialog, source, now: now, type: type)
  end

  def on_saved({next, %{id: id}}, dialog, ok_fn) do
    dialog
    |> msg_key(next, id)
    |> ChangeTracker.promise(ok_fn)
  end

  def await_saved({next, %{id: id}}, dialog) do
    dialog
    |> msg_key(next, id)
    |> ChangeTracker.await()
  end

  def read({index, %Message{} = msg}, identity, side, peer_key) when side in [:a_copy, :b_copy] do
    is_mine? = (side == :a_copy and msg.is_a_to_b?) or (side == :b_copy and !msg.is_a_to_b?)

    author_pub_key =
      if is_mine?,
        do: Identity.pub_key(identity),
        else: peer_key

    %PrivateMessage{
      timestamp: msg.timestamp,
      type: msg.type,
      index: index,
      id: msg.id,
      is_mine?: is_mine?,
      content:
        msg[side]
        |> Utils.decrypt_signed(identity, author_pub_key)
    }
  rescue
    _ ->
      ("[chat] [sign] Signature check failed " <> inspect({msg, side, identity, peer_key}))
      |> Logger.error()

      nil
  end

  def read(
        %Dialog{} = dialog,
        %Identity{} = me,
        before,
        amount
      ) do
    side = dialog |> Dialog.my_side(me)

    dialog
    |> get_messages(before, amount)
    |> Enum.map(fn {{_, _, index, _}, message} ->
      read({index, message}, me, side, Dialog.peer_key(dialog, side))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
  end

  def get_message(%Dialog{} = dialog, {index, id}) do
    msg_key(dialog, index, id)
    |> Db.get()
  end

  def get_next_message(%Dialog{} = dialog, {index, id}, predicate) do
    Db.get_next(
      msg_key(dialog, index, id),
      msg_key(dialog, nil, "some"),
      predicate
    )
  end

  def get_prev_message(%Dialog{} = dialog, {index, id}, predicate) do
    Db.get_prev(
      msg_key(dialog, index, id),
      msg_key(dialog, 0, 0),
      predicate
    )
  end

  def delete(%Dialog{} = dialog, %Identity{} = author, msg_id) do
    fn msg, index, key ->
      side = Dialog.my_side(dialog, author)

      {index, msg}
      |> read(author, side, Dialog.peer_key(dialog, side))
      |> Content.delete([dialog.a_key |> Utils.hash(), dialog.b_key |> Utils.hash()])

      Db.delete(key)
      :ok
    end
    |> change_my_message(author, dialog, msg_id)
  end

  def update_message(message, msg_id, %Identity{} = author, %Dialog{} = dialog) do
    fn msg, index, _key ->
      side = Dialog.my_side(dialog, author)

      {index, msg}
      |> read(author, side, Dialog.peer_key(dialog, side))
      |> Content.delete([dialog.a_key |> Utils.hash(), dialog.b_key |> Utils.hash()])

      type = DryStorable.type(message)

      message
      |> DryStorable.content()
      |> add_message(dialog, author, type: type, now: msg.timestamp, id: msg.id, index: index)
    end
    |> change_my_message(author, dialog, msg_id)
  end

  def msg_key(%Dialog{} = dialog, index, 0),
    do: {@db_prefix, dialog |> Dialog.dialog_key(), index, 0}

  def msg_key(%Dialog{} = dialog, index, id),
    do: {@db_prefix, dialog |> Dialog.dialog_key(), index, id |> Utils.binhash()}

  defp change_my_message(action_fn, author, dialog, {index, id}) do
    key = dialog |> msg_key(index, id)
    msg = Db.get(key)

    case dialog |> Dialog.is_mine?(msg, author) do
      true -> action_fn.(msg, index, key)
      _ -> nil
    end
  end

  defp add_message(
         content,
         %Dialog{a_key: a_key, b_key: a_key} = dialog,
         %Identity{} = source,
         opts
       ) do
    a_copy = content |> Utils.encrypt_and_sign(a_key, source)

    Message.a_to_b(a_copy, a_copy, opts)
    |> store_message(dialog, opts[:index])
  end

  defp add_message(
         content,
         %Dialog{a_key: a_key, b_key: b_key} = dialog,
         %Identity{} = source,
         opts
       ) do
    a_copy = content |> Utils.encrypt_and_sign(a_key, source)
    b_copy = content |> Utils.encrypt_and_sign(b_key, source)

    dialog
    |> Dialog.my_side(source)
    |> case do
      :a_copy -> Message.a_to_b(a_copy, b_copy, opts)
      :b_copy -> Message.b_to_a(a_copy, b_copy, opts)
    end
    |> store_message(dialog, opts[:index])
  end

  defp store_message(%{id: id} = msg, dialog, index) do
    next = index || Ordering.next({@db_prefix, dialog |> Dialog.dialog_key()})

    dialog
    |> msg_key(next, id)
    |> Db.put(msg)

    {next, msg}
  end

  defp get_messages(dialog, {max_index, id}, amount) do
    {
      msg_key(dialog, 0, 0),
      msg_key(dialog, max_index, id)
    }
    |> Db.select(amount)
  end
end
