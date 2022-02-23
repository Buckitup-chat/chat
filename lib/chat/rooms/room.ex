defmodule Chat.Rooms.Room do
  @moduledoc "Room struct"

  alias Chat.Identity
  alias Chat.Utils

  @derive {Inspect, only: [:name, :messages, :users]}
  defstruct [:admin_hash, :name, :pub_key, :messages, :users]

  def create(%Identity{} = admin, %Identity{name: name} = room) do
    admin_hash = admin |> Identity.pub_key() |> Utils.hash()

    %__MODULE__{
      admin_hash: admin_hash,
      name: name,
      pub_key: room |> Identity.pub_key(),
      messages: [],
      users: [admin_hash]
    }
  end
end
