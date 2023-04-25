defmodule Chat.Rooms.RoomRequest do
  @moduledoc """
  Room request structure
  """
  alias Chat.Card
  alias Chat.Identity

  defstruct requester_key: nil, pending?: true, ciphered_room_identity: nil

  def new(%Identity{} = requester), do: new(requester |> Identity.pub_key())
  def new(%Card{} = requester), do: new(requester |> Card.pub_key())
  def new(requester_key), do: %__MODULE__{requester_key: requester_key}
end
