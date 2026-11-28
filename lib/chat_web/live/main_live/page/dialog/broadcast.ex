defmodule ChatWeb.MainLive.Page.Dialog.Broadcast do
  @moduledoc """
  Dialog PubSub: the dialog topic and the new/updated/deleted message broadcasts
  (with their activity log entries).

  Used by `ChatWeb.MainLive.Page.Dialog` (subscribe/unsubscribe the topic) and
  `ChatWeb.MainLive.Page.Dialog.MessageActions` (broadcast after a change).
  """

  alias Chat.Broadcast
  alias Chat.Dialogs
  alias Chat.Log
  alias Phoenix.PubSub

  def dialog_topic(%Dialogs.Dialog{} = dialog) do
    Broadcast.Topic.dialog(dialog)
  end

  def broadcast_new_message(message, dialog, me, time) do
    Chat.Broadcast.new_dialog_message(message, dialog)

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
