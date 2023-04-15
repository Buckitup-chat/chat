defmodule Chat.Rooms.Room do
  @moduledoc "Room struct"

  use StructAccess

  alias Chat.Identity
  alias Chat.Rooms.RoomRequest

  @type room_type() :: :public | :request | :private
  @type t() :: %__MODULE__{
          admin: String.t(),
          name: String.t(),
          pub_key: String.t(),
          requests: list(),
          type: room_type()
        }

  @derive {Inspect, only: [:name, :type]}
  defstruct [:admin, :name, :pub_key, :hash, :requests, type: :public]

  def create(%Identity{} = admin, %Identity{name: name} = room, type \\ :public) do
    %__MODULE__{
      admin: admin |> Identity.pub_key(),
      name: name,
      pub_key: room |> Identity.pub_key(),
      requests: [],
      type: type,
      hash: room |> Identity.pub_key() |> hash()
    }
  end

  def add_request(%__MODULE__{type: :private} = room, _), do: room

  def add_request(%__MODULE__{requests: requests} = room, %Identity{} = me) do
    %{room | requests: [RoomRequest.new(me) | requests]}
  end

  def get_request(%__MODULE__{requests: requests}, user_public_key) do
    Enum.find(requests, &match?(%RoomRequest{requester_key: ^user_public_key}, &1))
  end

  def is_requested_by?(%__MODULE__{requests: requests}, user_public_key) do
    requests
    |> Enum.any?(&match?(%RoomRequest{requester_key: ^user_public_key}, &1))
  end

  def is_requested_by?(_, _), do: false

  def list_pending_requests(%__MODULE__{requests: requests, type: type})
      when type in [:public, :request] do
    requests
    |> Enum.filter(&match?(%RoomRequest{pending?: true}, &1))
  end

  def list_pending_requests(_), do: []

  def list_approved_requests_for(%__MODULE__{requests: requests}, user_public_key) do
    requests
    |> Enum.filter(&match?(%RoomRequest{requester_key: ^user_public_key, pending?: false}, &1))
  end

  def approve_request(
        %__MODULE__{requests: requests, type: type} = room,
        user_public_key,
        %Identity{} = room_identity,
        opts
      )
      when type in [:public, :request] do
    public_only? = Keyword.get(opts, :public_only, false)

    if public_only? and type != :public do
      room
    else
      new_requests =
        requests
        |> Enum.map(fn
          %RoomRequest{requester_key: ^user_public_key, pending?: true} ->
            %RoomRequest{
              requester_key: user_public_key,
              pending?: false,
              ciphered_room_identity: cipher_identity_with_key(room_identity, user_public_key)
            }

          x ->
            x
        end)

      %{room | requests: new_requests}
    end
  end

  def approve_request(room, _, _, _), do: room

  def clear_approved_request(%__MODULE__{type: :private} = room, _), do: room

  def clear_approved_request(
        %__MODULE__{requests: requests} = room,
        %Identity{public_key: user_public_key} = _me
      ) do
    new_requests =
      requests
      |> Enum.reject(&match?(%RoomRequest{requester_key: ^user_public_key, pending?: false}, &1))

    %{room | requests: new_requests}
  end

  def hash(pub_key), do: Base.encode16(pub_key, case: :lower)

  def cipher_identity(%Identity{} = room_identity, secret) do
    room_identity
    |> Identity.priv_key_to_string()
    |> Enigma.cipher(secret)
  end

  def decipher_identity(ciphered, secret) do
    ciphered
    |> Enigma.decipher(secret)
    |> then(&["", &1])
    |> Identity.from_strings()
  end

  defp cipher_identity_with_key(room_identity, user_public_key) do
    secret = Enigma.compute_secret(room_identity.private_key, user_public_key)

    cipher_identity(room_identity, secret)
  end

  def decipher_identity_with_key(ciphered, %Identity{} = me, room_public_key) do
    secret = Enigma.compute_secret(me.private_key, room_public_key)

    decipher_identity(ciphered, secret)
  end
end

defimpl Enigma.Hash.Protocol, for: Chat.Rooms.Room do
  def to_iodata(room), do: room.pub_key
end
