defmodule ChatWeb.MainLive.Page.Room.Broadcast do
  @moduledoc """
  Room PubSub: the per-room topic and the new/updated/deleted message broadcasts
  (with their activity log entries).

  Used by `ChatWeb.MainLive.Page.Room` (subscribe on init, unsubscribe on close) and
  `ChatWeb.MainLive.Page.Room.MessageActions` (broadcast after a change).
  """

  alias Chat.Log

  alias Phoenix.PubSub

  def room_topic(pub_key) do
    pub_key
    |> Base.encode16(case: :lower)
    |> then(&"room:#{&1}")
  end

  def broadcast_message_updated(msg_id, pub_key, me, time) do
    {:updated_message, msg_id}
    |> room_broadcast(pub_key)

    Log.update_room_message(me, time, pub_key)
  end

  def broadcast_new_message(message, pub_key, me, time) do
    {:new_message, message}
    |> room_broadcast(pub_key)

    Log.message_room(me, time, pub_key)
  end

  def broadcast_deleted_message(msg_id, pub_key, me, time) do
    {:deleted_message, msg_id}
    |> room_broadcast(pub_key)

    Log.delete_room_message(me, time, pub_key)
  end

  defp room_broadcast(message, pub_key) do
    PubSub.broadcast!(
      Chat.PubSub,
      pub_key |> room_topic(),
      {:room, message}
    )
  end
end
