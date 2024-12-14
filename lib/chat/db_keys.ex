defmodule Chat.DbKeys do
  @moduledoc """
  DB keys
  """

  alias Chat.Proto.Identify
  alias Chat.Rooms.Message

  def room_message(msg, index: index, room: room_ref) do
    {
      room_ref |> Identify.pub_key(),
      index,
      msg
    }
    |> case do
      {room_key, index, 0} ->
        {:room_message, room_key, index, 0}

      {room_key, index, %Message{id: msg_id}} ->
        {:room_message, room_key, index, msg_id |> Enigma.hash()}

      {room_key, index, msg_id} ->
        {:room_message, room_key, index, msg_id |> Enigma.hash()}
    end
  end

  def room_message_prefix(room_ref) do
    {:room_message, room_ref |> Identify.pub_key()}
  end

  def memo(key), do: {:memo, key}
  def file(key), do: {:file, key}
end
