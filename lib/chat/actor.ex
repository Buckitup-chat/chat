defmodule Chat.Actor do
  @moduledoc "Perpresents acting person in the system"

  alias Chat.Identity
  alias Chat.Utils
  alias X509.PrivateKey

  defstruct [:me, rooms: []]

  def new(%Identity{} = me, rooms) do
    %__MODULE__{
      me: me,
      rooms: rooms
    }
  end

  def to_json(%__MODULE__{me: %Identity{name: name, priv_key: priv_key}, rooms: rooms}) do
    [
      [name, private_key_to_string(priv_key)],
      rooms
      |> Enum.map(fn %Identity{priv_key: key} -> private_key_to_string(key) end)
    ]
    |> Jason.encode!()
  end

  def from_json(json) do
    [[name, key], room_keys] = Jason.decode!(json)
    me = %Identity{name: name, priv_key: private_key_from_string(key)}

    rooms =
      room_keys
      |> Enum.map(fn key -> %Identity{name: "", priv_key: private_key_from_string(key)} end)

    new(me, rooms)
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
end
