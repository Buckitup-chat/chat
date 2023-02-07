defmodule Chat.Rooms.Room do
  @moduledoc "Room struct"

  alias Chat.Identity
  alias Chat.Utils

  @type room_type() :: :public | :request | :private
  @type t() :: %__MODULE__{
          admin_hash: String.t(),
          name: String.t(),
          pub_key: String.t(),
          requests: list(),
          type: room_type()
        }

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

  def get_request(%__MODULE__{requests: requests}, user_hash) do
    Enum.find(requests, fn {hash, _, _} -> hash == user_hash end)
  end

  def is_requested_by?(%__MODULE__{requests: requests}, user_hash) do
    requests
    |> Enum.any?(fn {hash, _, _} -> hash == user_hash end)
  end

  def is_requested_by?(_, _), do: false

  def list_pending_requests(%__MODULE__{requests: requests, type: type})
      when type in [:public, :request] do
    requests
    |> Enum.map(fn
      {hash, key, :pending} -> {hash, key}
      {_, _, _} -> nil
    end)
    |> Enum.reject(&(&1 == nil))
  end

  def list_pending_requests(_), do: []

  def list_approved_requests_for(%__MODULE__{requests: requests}, user_hash) do
    requests
    |> Enum.filter(&match?({^user_hash, _, {_, _}}, &1))
  end

  def approve_request(
        %__MODULE__{requests: requests, type: type} = room,
        user_hash,
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
          {^user_hash, key, :pending} -> {user_hash, key, room_identity |> encrypt_identity(key)}
          {_, _, _} = x -> x
        end)

      %{room | requests: new_requests}
    end
  end

  def approve_request(room, _, _, _), do: room

  def join_approved_request(%__MODULE__{type: :private} = room, _), do: room

  def join_approved_request(%__MODULE__{requests: requests} = room, %Identity{} = me) do
    user_hash = me |> Identity.pub_key() |> Utils.hash()

    new_requests =
      requests
      |> Enum.filter(fn {hash, _, _} -> hash !== user_hash end)

    %{room | requests: new_requests}
  end

  def decrypt_identity({encrypted_secret, blob}, %Identity{priv_key: key}) do
    secret = encrypted_secret |> Utils.decrypt(key)

    blob
    |> Utils.decrypt_blob(secret)
    |> Identity.from_strings()
  end

  defp encrypt_identity(room_identity, key) do
    {blob, secret} =
      room_identity
      |> Identity.to_strings()
      |> Utils.encrypt_blob()

    {secret |> Utils.encrypt(key), blob}
  end
end
