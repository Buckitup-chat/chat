defmodule Chat.Rooms.Room do
  @moduledoc "Room struct"

  alias Chat.Identity
  alias Chat.Images
  alias Chat.Rooms.Message
  alias Chat.Rooms.PlainMessage
  alias Chat.User
  alias Chat.Utils

  @derive {Inspect, only: [:name, :messages, :users]}
  defstruct [:admin_hash, :name, :pub_key, :messages, :users, :requests]

  def create(%Identity{} = admin, %Identity{name: name} = room) do
    admin_hash = admin |> Identity.pub_key() |> Utils.hash()

    %__MODULE__{
      admin_hash: admin_hash,
      name: name,
      pub_key: room |> Identity.pub_key(),
      messages: [],
      users: [admin_hash],
      requests: []
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

  def add_image(
        %__MODULE__{pub_key: room_key, messages: messages} = room,
        %Identity{} = author,
        data
      ) do
    {key, secret} = Images.add(data)

    msg =
      %{key => secret |> Base.url_encode64()}
      |> Jason.encode!()

    author_hash = author |> Identity.pub_key() |> Utils.hash()
    encrypted = Chat.User.encrypt(msg, room_key)
    message = Message.new(author_hash, encrypted, type: :image)

    %{room | messages: [message | messages]}
  end

  def glimpse(%__MODULE__{messages: [last | _]} = room), do: %{room | messages: [last]}

  def read(%__MODULE__{messages: messages}, identity, before, amount) do
    messages
    |> Utils.page(before, amount)
    |> Enum.map(fn %Message{} = msg ->
      %PlainMessage{
        timestamp: msg.timestamp,
        type: msg.type,
        author_hash: msg.author_hash,
        id: msg.id,
        content: msg.encrypted |> Chat.User.decrypt(identity)
      }
    end)
  end

  def add_request(%__MODULE__{requests: requests} = room, %Identity{} = me) do
    key = me |> Identity.pub_key()
    hash = key |> Utils.hash()

    %{room | requests: [{hash, key, :pending} | requests]}
  end

  def is_requested_by?(%__MODULE__{requests: requests}, user_hash) do
    requests
    |> Enum.any?(fn {hash, _, _} -> hash == user_hash end)
  end

  def approve_requests(%__MODULE__{requests: requests} = room, %Identity{} = room_identity) do
    new_requests =
      requests
      |> Enum.reject(fn
        {_, _, :joined} -> true
        {_, _, _} -> false
      end)
      |> Enum.map(fn
        {hash, key, :pending} ->
          {blob, secret} =
            room_identity
            |> :erlang.term_to_binary()
            |> Utils.encrypt_blob()

          encrypted = {secret |> User.encrypt(key), blob}

          {hash, key, encrypted}

        {_, _, _} = x ->
          x
      end)

    %{room | requests: new_requests}
  end

  def join_approved_requests(%__MODULE__{requests: requests} = room, %Identity{} = me) do
    pub_key = me |> Identity.pub_key()
    hash = pub_key |> Utils.hash()

    {new_requests, rooms} =
      requests
      |> Enum.reduce({[], []}, fn
        {^hash, ^pub_key, {enc_secret, blob}}, {reqs, rooms} ->
          secret =
            enc_secret
            |> User.decrypt(me)

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
