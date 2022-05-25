defmodule Chat.Rooms.Room do
  @moduledoc "Room struct"

  alias Chat.Identity
  alias Chat.Utils

  @type room_type() :: :public | :request | :private

  @derive {Inspect, only: [:name, :type]}
  defstruct [:admin_hash, :name, :pub_key, :requests, type: :public]

  def create(%Identity{} = admin, %Identity{name: name} = room, type \\ :public) do
    admin_hash = admin |> Identity.pub_key() |> Utils.hash()

    %__MODULE__{
      admin_hash: admin_hash,
      name: name,
      pub_key: room |> Identity.pub_key(),
      requests: [],
      type: type
    }
  end

  def add_request(%__MODULE__{type: :private} = room, _), do: room

  def add_request(%__MODULE__{requests: requests} = room, %Identity{} = me) do
    key = me |> Identity.pub_key()
    hash = key |> Utils.hash()

    %{room | requests: [{hash, key, :pending} | requests]}
  end

  def is_requested_by?(%__MODULE__{requests: requests}, user_hash) do
    requests
    |> Enum.any?(fn {hash, _, _} -> hash == user_hash end)
  end

  def is_requested_by?(_, _), do: false

  def approve_requests(
        %__MODULE__{requests: requests, type: :public} = room,
        %Identity{} = room_identity
      ) do
    new_requests =
      requests
      |> Enum.map(fn
        {hash, key, :pending} ->
          {blob, secret} =
            room_identity
            |> :erlang.term_to_binary()
            |> Utils.encrypt_blob()

          encrypted = {secret |> Utils.encrypt(key), blob}

          {hash, key, encrypted}

        {_, _, _} = x ->
          x
      end)

    %{room | requests: new_requests}
  end

  def approve_requests(room, _), do: room

  def join_approved_requests(%__MODULE__{type: :private} = room, _), do: {room, []}

  def join_approved_requests(%__MODULE__{requests: requests} = room, %Identity{} = me) do
    pub_key = me |> Identity.pub_key()
    hash = pub_key |> Utils.hash()

    {new_requests, rooms} =
      requests
      |> Enum.reduce({[], []}, fn
        {^hash, ^pub_key, {enc_secret, blob}}, {reqs, rooms} ->
          secret =
            enc_secret
            |> Utils.decrypt(me)

          decrypted =
            blob
            |> Utils.decrypt_blob(secret)
            |> :erlang.binary_to_term()

          {reqs, [decrypted | rooms]}

        x, {reqs, rooms} ->
          {[x | reqs], rooms}
      end)

    {
      %{room | requests: new_requests},
      rooms
    }
  end
end
