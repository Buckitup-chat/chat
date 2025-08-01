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

  @deprecated "should use Chat.store_parcel"
  def on_saved({next, %{id: id}}, dialog, ok_fn) do
    dialog
    |> msg_key(next, id)
    |> ChangeTracker.promise(ok_fn)
  end

  @deprecated "should use copying.await"
  def await_saved({next, %{id: id}}, dialog) do
    dialog
    |> msg_key(next, id)
    |> ChangeTracker.await()
  end

  def read({_index, nil}, _user_identity, _dialog), do: nil

  def read({index, %Message{} = msg}, %Identity{} = identity, %Dialog{a_key: a_key, b_key: b_key}) do
    {peer_key, is_mine?} =
      case {identity.public_key, a_key, b_key} do
        {my_key, my_key, peer_key} -> {peer_key, msg.is_a_to_b?}
        {my_key, peer_key, my_key} -> {peer_key, not msg.is_a_to_b?}
      end

    author_key = (is_mine? && identity.public_key) || peer_key

    with {:ok, content} <-
           Enigma.decrypt_signed(
             msg.content,
             identity.private_key,
             peer_key,
             author_key
           ),
         message <- %PrivateMessage{
           timestamp: msg.timestamp,
           type: msg.type,
           index: index,
           id: msg.id,
           is_mine?: is_mine?,
           content: content
         } do
      message
    else
      _ ->
        [
          "[chat] ",
          "[sign] ",
          "Signature check failed ",
          inspect({msg, is_mine?, identity.public_key, peer_key})
        ]
        |> Logger.error()

        nil
    end
  end

  def read(
        %Dialog{} = dialog,
        %Identity{} = me,
        before,
        amount
      ) do
    dialog
    |> get_messages(before, amount)
    |> Enum.map(fn {{_, _, index, _}, message} ->
      read({index, message}, me, dialog)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
  end

  def list_room_invites(%Dialog{} = dialog, %Identity{} = me) do
    dialog
    |> get_room_invites()
    |> Enum.filter(fn {_, message} -> message.type == :room_invite end)
    |> Enum.map(fn {{_, _, index, _}, message} -> read({index, message}, me, dialog) end)
    |> Enum.reject(&is_nil/1)
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
      {index, msg}
      |> read(author, dialog)
      |> Content.delete([dialog.a_key, dialog.b_key], msg.id)

      Db.delete(key)
      :ok
    end
    |> change_my_message(author, dialog, msg_id)
  end

  def update_message(message, msg_id, %Identity{} = author, %Dialog{} = dialog) do
    fn msg, index, _key ->
      {index, msg}
      |> read(author, dialog)
      |> Content.delete([dialog.a_key, dialog.b_key], msg.id)

      type = DryStorable.type(message)

      message
      |> DryStorable.content()
      |> add_message(dialog, author, type: type, now: msg.timestamp, id: msg.id, index: index)
    end
    |> change_my_message(author, dialog, msg_id)
  end

  def content_to_message(content, %Identity{} = author, %Dialog{} = dialog, opts) do
    case {dialog.a_key, dialog.b_key, author.public_key} do
      {dst, dst, dst} ->
        content
        |> Enigma.encrypt_and_sign(author.private_key, dst)
        |> Message.a_to_b(opts)

      {dst, src, src} ->
        content
        |> Enigma.encrypt_and_sign(author.private_key, dst)
        |> Message.b_to_a(opts)

      {src, dst, src} ->
        content
        |> Enigma.encrypt_and_sign(author.private_key, dst)
        |> Message.a_to_b(opts)
    end
  end

  def msg_key(%Dialog{} = dialog, index, 0),
    do: {@db_prefix, dialog |> Enigma.hash(), index, 0}

  def msg_key(%Dialog{} = dialog, index, id),
    do: {@db_prefix, dialog |> Enigma.hash(), index, id |> Enigma.hash()}

  defp change_my_message(action_fn, %Identity{public_key: public_key}, dialog, {index, id}) do
    key = dialog |> msg_key(index, id)
    msg = Db.get(key)

    case {msg.is_a_to_b?, public_key == dialog.a_key, public_key == dialog.b_key} do
      {true, true, _} -> action_fn.(msg, index, key)
      {false, false, true} -> action_fn.(msg, index, key)
      _ -> nil
    end
  end

  defp add_message(content, %Dialog{} = dialog, %Identity{} = author, opts) do
    content
    |> content_to_message(author, dialog, opts)
    |> store_message(dialog, opts[:index])
  end

  defp store_message(%{id: id} = msg, dialog, index) do
    next = index || Ordering.next({@db_prefix, dialog |> Enigma.hash()})

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

  defp get_room_invites(dialog) do
    {
      msg_key(dialog, 0, 0),
      msg_key(dialog, nil, 0)
    }
    |> Db.list()
  end
end
