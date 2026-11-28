defmodule ChatWeb.ProxyLive.Page.Dialog.Broadcast do
  @moduledoc """
  Proxy dialog PubSub: the dialog topic and the new/updated/deleted message broadcasts
  (with their activity log entries).

  Used by `ChatWeb.ProxyLive.Page.Dialog` (join/leave the topic) and
  `ChatWeb.ProxyLive.Page.Dialog.MessageActions` (broadcast after a change).
  """

  alias Chat.Broadcast
  alias Chat.Dialogs
  alias Chat.Log
  alias Phoenix.PubSub

  def dialog_topic(%Dialogs.Dialog{} = dialog) do
    Broadcast.Topic.dialog(dialog)
  end

  def broadcast_new_message(nil, _, _, _), do: nil

  def broadcast_new_message(message, dialog, me, time) do
    {:new_dialog_message, message}
    |> dialog_broadcast(dialog)

    Log.message_direct(me, time, Dialogs.peer(dialog, me))
  end

  def broadcast_message_updated(message_id, dialog, me, time) do
    {:updated_dialog_message, message_id}
    |> dialog_broadcast(dialog)

    Log.update_message_direct(me, time, Dialogs.peer(dialog, me))
  end

  def broadcast_message_deleted(message_id, dialog, me, time) do
    {:deleted_dialog_message, message_id}
    |> dialog_broadcast(dialog)

    Log.delete_message_direct(me, time, Dialogs.peer(dialog, me))
  end

  defp dialog_broadcast(message, dialog) do
    PubSub.broadcast!(
      Chat.PubSub,
      dialog |> dialog_topic(),
      {:dialog, message}
    )
  end
end
