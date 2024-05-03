defmodule Chat.DbKeys do
  @moduledoc """
  DB keys
  """

  def room_message(msg, index: index, room: room_ref) do
    {
      room_ref |> Chat.Proto.Identify.pub_key(),
      index,
      msg
    }
    |> case do
      {room_key, index, 0} ->
        {:room_message, room_key, index, 0}

      {room_key, index, %Chat.Rooms.Message{id: msg_id}} ->
        {:room_message, room_key, index, msg_id |> Enigma.hash()}

      {room_key, index, msg_id} ->
        {:room_message, room_key, index, msg_id |> Enigma.hash()}
    end
  end

  def room_message_prefix(room_ref) do
    {:room_message, room_ref |> Chat.Proto.Identify.pub_key()}
  end
end
