defmodule Chat.Dialogs do
  @moduledoc "Context for dialogs"

  alias Chat.Card
  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.DialogMessaging
  alias Chat.Dialogs.Message
  alias Chat.Dialogs.Registry
  alias Chat.Identity

  def find_or_open(%Identity{} = me) do
    find_or_open(me, Card.from_identity(me))
  end

  def find_or_open(%Identity{} = src, %Card{} = dst) do
    case Registry.find(src, dst) do
      nil ->
        open(src, dst)
        |> tap(&update/1)

      dialog ->
        dialog
    end
  end

  def open(%Identity{} = src, %Card{} = dst) do
    Dialog.start(src, dst)
  end

  defdelegate update(dialog), to: Registry

  defdelegate add_new_message(message, author, dialog), to: DialogMessaging
  defdelegate update_message(message, msg_id, author, dialog), to: DialogMessaging
  defdelegate delete(dialog, author, msg_time_id), to: DialogMessaging
  defdelegate await_saved(added_message, dialog), to: DialogMessaging
  defdelegate on_saved(added_message, dialog, action), to: DialogMessaging

  def read(
        %Dialog{} = dialog,
        %Identity{} = reader,
        before \\ {nil, 0},
        amount \\ 1000
      ),
      do: DialogMessaging.read(dialog, reader, before, amount)

  def read_message(%Dialog{} = dialog, {index, %Message{} = message}, %Identity{} = me) do
    DialogMessaging.read({index, message}, me, dialog)
  end

  def read_message(%Dialog{} = dialog, {index, msg_id} = _msg_id, %Identity{} = me) do
    message = DialogMessaging.get_message(dialog, {index, msg_id})
    DialogMessaging.read({index, message}, me, dialog)
  end

  def read_prev_message(
        %Dialog{} = dialog,
        {index, msg_id} = _msg_id,
        %Identity{} = me,
        predicate
      ) do
    DialogMessaging.get_prev_message(dialog, {index, msg_id}, predicate)
    |> case do
      nil ->
        nil

      message ->
        DialogMessaging.read(message, me, dialog)
    end
  end

  def read_next_message(
        %Dialog{} = dialog,
        {index, msg_id} = _msg_id,
        %Identity{} = me,
        predicate
      ) do
    DialogMessaging.get_next_message(dialog, {index, msg_id}, predicate)
    |> case do
      nil ->
        nil

      message ->
        DialogMessaging.read(message, me, dialog)
    end
  end

  def key(%Dialog{} = dialog) do
    dialog
    |> Enigma.hash()
  end

  def peer(dialog, %Identity{} = me), do: peer(dialog, me |> Identity.pub_key())
  def peer(dialog, %Card{pub_key: key}), do: peer(dialog, key)
  def peer(%Dialog{a_key: my_key, b_key: peer_key}, my_key), do: peer_key
  def peer(%Dialog{a_key: peer_key, b_key: my_key}, my_key), do: peer_key
end
