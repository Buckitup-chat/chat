defmodule Chat.Rooms.Room do
  @moduledoc "Room struct"

  alias Chat.Identity
  alias Chat.Rooms.Message
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

  def add_text(
        %__MODULE__{pub_key: room_key, messages: messages} = room,
        %Identity{} = author,
        text
      ) do
    author_hash = author |> Identity.pub_key() |> Utils.hash()
    encrypted = Chat.User.encrypt(text, room_key)
    message = Message.new(author_hash, encrypted, type: :text)

    %{room | messages: [message | messages]}
  end
end
