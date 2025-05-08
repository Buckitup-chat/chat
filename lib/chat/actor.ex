defmodule Chat.Actor do
  @moduledoc "Perpresents acting person in the system"

  alias Chat.Identity

  defstruct [:me, rooms: [], contacts: %{}, payload: %{}]

  def new(%Identity{} = me, rooms, contacts \\ %{}, payload \\ %{}) do
    %__MODULE__{
      me: me,
      rooms: rooms,
      contacts: contacts,
      payload: payload
    }
  end

  def to_json(%__MODULE__{
        me: %Identity{} = identity,
        rooms: rooms,
        contacts: contacts,
        payload: payload
      }) do
    [
      identity |> Identity.to_strings(),
      rooms |> Enum.map(&(&1 |> Identity.priv_key_to_string())),
      contacts,
      payload
    ]
    |> Jason.encode!()
  end

  def from_json(json) do
    case Jason.decode!(json) do
      [me, rooms, contacts, payload] -> [me, rooms, contacts, payload]
      [me, rooms, contacts] -> [me, rooms, contacts, %{}]
      [me, rooms] -> [me, rooms, %{}, %{}]
      _ -> nil
    end
    |> then(fn
      [me, rooms, contacts, payload] ->
        new(
          Identity.from_strings(me),
          rooms |> Enum.map(&Identity.from_strings(["", &1])),
          contacts,
          payload
        )
      _ -> nil
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
