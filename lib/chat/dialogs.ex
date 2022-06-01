defmodule Chat.Dialogs do
  @moduledoc "Context for dialogs"

  alias Chat.Card
  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Message
  alias Chat.Dialogs.Registry
  alias Chat.Identity
  alias Chat.Utils

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

  defdelegate add_text(dialog, src, text, now \\ DateTime.utc_now()), to: Dialog
  defdelegate add_memo(dialog, src, memo, now \\ DateTime.utc_now()), to: Dialog
  defdelegate add_file(dialog, src, data, now \\ DateTime.utc_now()), to: Dialog
  defdelegate add_image(dialog, src, data, now \\ DateTime.utc_now()), to: Dialog
  defdelegate add_room_invite(dialog, src, room_identity, now \\ DateTime.utc_now()), to: Dialog

  defdelegate update(dialog, author, msg_time_id, content), to: Dialog
  defdelegate delete(dialog, author, msg_time_id), to: Dialog

  def read(
        %Dialog{} = dialog,
        %Identity{} = reader,
        before \\ {nil, 0},
        amount \\ 1000
      ),
      do: Dialog.read(dialog, reader, before, amount)

  def read_message(%Dialog{} = dialog, {time, msg_id} = _msg_id, %Identity{} = me) do
    message = Dialog.get_message(dialog, {time, msg_id})
    side = Dialog.my_side(dialog, me)
    Dialog.read(message, me, side, peer(dialog, me))
  end

  def read_message(%Dialog{} = dialog, %Message{} = message, %Identity{} = me) do
    side = Dialog.my_side(dialog, me)
    Dialog.read(message, me, side, peer(dialog, me))
  end

  def key(%Dialog{} = dialog) do
    dialog
    |> Dialog.dialog_key()
    |> Utils.hash()
  end

  def peer(dialog, %Identity{} = me), do: peer(dialog, me |> Identity.pub_key())
  def peer(dialog, %Card{pub_key: key}), do: peer(dialog, key)
  def peer(%Dialog{a_key: my_key, b_key: peer_key}, my_key), do: peer_key
  def peer(%Dialog{a_key: peer_key, b_key: my_key}, my_key), do: peer_key
end
