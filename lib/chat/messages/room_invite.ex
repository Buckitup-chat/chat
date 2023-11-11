defmodule Chat.Messages.RoomInvite do
  @moduledoc "Room invite message"

  @type t :: %__MODULE__{}

  defstruct room_identity: nil, timestamp: 0

  def new(identity) do
    %__MODULE__{room_identity: identity}
  end

  def new(identity, timestamp) do
    %__MODULE__{room_identity: identity, timestamp: timestamp}
  end
end

defimpl Chat.DryStorable, for: Chat.Messages.RoomInvite do
  alias Chat.Identity
  alias Chat.Messages.RoomInvite
  alias Chat.Content.RoomInvites
  alias Chat.Utils.StorageId

  def content(%RoomInvite{} = msg) do
    msg.room_identity
    |> Identity.to_strings()
    |> RoomInvites.add()
    |> StorageId.to_json()
  end

  def timestamp(%RoomInvite{} = msg), do: msg.timestamp

  @spec type(Chat.Messages.RoomInvite.t()) :: atom()
  def type(%RoomInvite{} = _), do: :room_invite
end
