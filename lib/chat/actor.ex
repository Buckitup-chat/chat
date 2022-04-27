defmodule Chat.Actor do
  @moduledoc "Perpresents acting person in the system"

  alias Chat.Identity
  alias Chat.Utils
  alias X509.PrivateKey
  alias X509.PublicKey

  defstruct [:me, rooms: [], contacts: %{}]

  def new(%Identity{} = me, rooms, contacts) do
    %__MODULE__{
      me: me,
      rooms: rooms,
      contacts: contacts
    }
  end

  def to_json(%__MODULE__{
        me: %Identity{name: name, priv_key: priv_key},
        rooms: rooms,
        contacts: contacts
      }) do
    [
      [name, private_key_to_string(priv_key)],
      rooms |> Enum.map(fn %Identity{priv_key: key} -> private_key_to_string(key) end),
      contacts |> Enum.map(fn {k, v} -> {k |> public_key_to_string(), v} end) |> Enum.into(%{})
    ]
    |> Jason.encode!()
  end

  def from_json(json) do
    [[name, key], room_keys, contacts] =
      case Jason.decode!(json) do
        [me, rooms, contacts] -> [me, rooms, contacts]
        [me, rooms] -> [me, rooms, %{}]
      end

    me = %Identity{name: name, priv_key: private_key_from_string(key)}

    rooms =
      room_keys
      |> Enum.map(fn key -> %Identity{name: "", priv_key: private_key_from_string(key)} end)

    contacts =
      contacts
      |> Enum.map(fn {key, name} -> {key |> public_key_from_string(), name} end)
      |> Enum.into(%{})

    new(me, rooms, contacts)
  end

  def to_encrypted_json(%__MODULE__{} = actor, password) when password in ["", nil, false],
    do: to_json(actor)

  def to_encrypted_json(%__MODULE__{} = actor, password) do
    actor
    |> to_json()
    |> Utils.encrypt_blob(password |> Utils.binhash())
  end

  def from_encrypted_json(data, password) when password in ["", nil, false], do: from_json(data)

  def from_encrypted_json(data, password) do
    data
    |> Utils.decrypt_blob(password |> Utils.binhash())
    |> from_json()
  end

  defp private_key_to_string(key) do
    key
    |> PrivateKey.to_der()
    |> Base.encode64()
  end

  defp private_key_from_string(string) do
    string
    |> Base.decode64!()
    |> PrivateKey.from_der!()
  end

  defp public_key_to_string(key) do
    key
    |> PublicKey.to_der()
    |> Base.encode64()
  end

  defp public_key_from_string(string) do
    string
    |> Base.decode64!()
    |> PublicKey.from_der!()
  end
end
