defmodule Chat.Messages.RoomRequest do
  @moduledoc "Room invite message"

  defstruct timestamp: 0

  def new(timestamp) do
    %__MODULE__{timestamp: timestamp}
  end
end

defimpl Chat.DryStorable, for: Chat.Messages.RoomRequest do
  alias Chat.Messages.RoomRequest

  def content(%RoomRequest{} = _msg) do
    ""
  end

  def timestamp(%RoomRequest{} = msg), do: msg.timestamp

  def type(%RoomRequest{} = _), do: :request
end
