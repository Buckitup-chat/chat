defmodule Chat.Actor do
  @moduledoc "Perpresents acting person in the system"

  alias Chat.Identity

  defstruct [:me, rooms: [], contacts: %{}]

  def new(%Identity{} = me, rooms, contacts) do
    %__MODULE__{
      me: me,
      rooms: rooms,
      contacts: contacts
    }
  end

  def to_json(%__MODULE__{
        me: %Identity{} = identity,
        rooms: rooms,
        contacts: contacts
      }) do
    [
      identity |> Identity.to_strings(),
      rooms |> Enum.map(&(&1 |> Identity.to_strings() |> Enum.at(1))),
      contacts
    ]
    |> Jason.encode!()
  end

  def from_json(json) do
    case Jason.decode!(json) do
      [me, rooms, contacts] -> [me, rooms, contacts]
      [me, rooms] -> [me, rooms, %{}]
    end
    |> then(fn me, rooms, contacts ->
      new(
        Identity.from_strings(me),
        rooms |> Enum.map(&Identity.from_strings(["", &1])),
        contacts
      )
    end)
  end

  def to_encrypted_json(%__MODULE__{} = actor, password) when password in ["", nil, false],
    do: to_json(actor)

  def to_encrypted_json(%__MODULE__{} = actor, password) do
    actor
    |> to_json()
    |> Enigma.cipher(password |> Enigma.hash())
  end

  def from_encrypted_json(data, password) when password in ["", nil, false], do: from_json(data)

  def from_encrypted_json(data, password) do
    data
    |> Enigma.decipher(password |> Enigma.hash())
    |> from_json()
  end
end
