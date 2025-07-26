defmodule Chat.SignedParcel do
  @moduledoc """
  A package of message with attachment and indexes.
  Signed by author. So can be checked for integrity.

  This module provides functionality for working with signed parcels, including:
  - Creating and signing parcels
  - Wrapping messages for dialog and room communication
  - Extracting messages from parcels
  - Validating parcel signatures and scopes
  - Managing message indexes

  The centralized message extraction functions (`extract_indexed_message/1` and `message_type/1`)
  provide a unified way to work with different types of messages in parcels.
  """

  alias Chat.Dialogs.DialogMessaging
  alias Chat.Dialogs.Message, as: DialogMessage
  alias Chat.Rooms.RoomMessages
  alias Chat.Identity
  alias Chat.Rooms.Message, as: RoomMessage

  defstruct data: [], sign: ""

  @type t() :: %__MODULE__{data: list(), sign: binary()}

  @doc """
  Wrap message into parcel.

  Options:
    * `type` - message type
    * `id` - message id
    * `index` - message index
  """
  def wrap_dialog_message(message, dialog, me, opts \\ []) do
    type = Chat.DryStorable.type(message)
    {content, data_list} = Chat.DryStorable.to_parcel(message)

    msg =
      DialogMessaging.content_to_message(content, me, dialog, opts |> Keyword.put(:type, type))

    msg_key = DialogMessaging.msg_key(dialog, opts |> Keyword.get(:index, :next), msg.id)

    Enum.reduce(data_list, [{msg_key, msg}], fn
      {{:memo, key}, _} = data, acc ->
        extra = Chat.MemoIndex.pack(dialog, key)
        [[data | extra] | acc]

      {{:room_invite, key}, _} = data, acc ->
        extra = Chat.RoomInviteIndex.pack(dialog, key)
        [[data | extra] | acc]

      x, acc ->
        [x | acc]
    end)
    |> List.flatten()
    |> Enum.sort()
    |> new()
    |> sign(me.private_key)
  end

  @doc """
  Wrap message into room parcel.

  Options:
    * `type` - message type
    * `id` - message id
    * `index` - message index
  """
  def wrap_room_message(message, room_identity, author, opts \\ []) do
    type = Chat.DryStorable.type(message)
    {content, data_list} = Chat.DryStorable.to_parcel(message)

    room_pub_key = Identity.pub_key(room_identity)

    encrypted_content =
      content
      |> Enigma.encrypt_and_bisign(author.private_key, room_identity.private_key)

    msg =
      RoomMessage.new(
        encrypted_content,
        author.public_key,
        opts |> Keyword.put(:type, type)
      )

    id = opts |> Keyword.get(:id, msg.id)
    index = opts |> Keyword.get(:index, :next)
    msg_key = RoomMessages.key(room_pub_key, index, id)

    Enum.reduce(data_list, [{msg_key, msg}], fn
      {{:memo, key}, _} = data, acc ->
        room = %Chat.Rooms.Room{pub_key: room_pub_key}
        extra = Chat.MemoIndex.pack(room, key)
        [[data | extra] | acc]

      x, acc ->
        [x | acc]
    end)
    |> List.flatten()
    |> Enum.sort()
    |> new()
    |> sign(author.private_key)
  end

  def sign_valid?(%__MODULE__{} = parcel, public_key) do
    Enigma.valid_sign?(
      parcel.sign,
      parcel |> Enigma.hash(),
      public_key
    )
  end

  def scope_valid?(%__MODULE__{data: items}, public_key) do
    case items do
      [{{:dialog_message, dialog_key, _, _}, %DialogMessage{type: :text}}] ->
        public_key in dialog_peer_keys(dialog_key)

      [
        {{:memo, _}, _},
        {{:memo_index, some_pkey, _}, true},
        {{:memo_index, other_okey, _}, true},
        {{:dialog_message, dialog_key, _, _}, %DialogMessage{type: :memo}}
      ] ->
        cond do
          some_pkey != public_key and other_okey != public_key -> false
          peers = dialog_peer_keys(dialog_key) -> some_pkey in peers and other_okey in peers
        end

      [
        {{:room_invite, _}, _},
        {{:room_invite_index, some_pkey, _}, _},
        {{:room_invite_index, other_okey, _}, _},
        {{:dialog_message, dialog_key, _, _}, %DialogMessage{type: :room_invite}}
      ] ->
        cond do
          some_pkey != public_key and other_okey != public_key -> false
          peers = dialog_peer_keys(dialog_key) -> some_pkey in peers and other_okey in peers
        end

      [{{:room_message, room_key, _, _}, %RoomMessage{type: :text}}] ->
        match?(%RoomMessage{author_key: ^public_key}, elem(List.last(items), 1)) or
          public_key == room_key

      [
        {{:memo, _}, _},
        {{:memo_index, room_key, _}, true},
        {{:room_message, room_key, _, _}, %RoomMessage{type: :memo}}
      ] ->
        match?(%RoomMessage{author_key: ^public_key}, elem(List.last(items), 1)) or
          public_key == room_key
    end
  end

  @doc """
  Gets the main item (message and its key) from a parcel.

  This function uses the centralized extraction logic to identify and return the main message item
  in a consistent way regardless of message type.

  ## Returns
  - A tuple of {{type, key, index, msg_id}, message} representing the main message item

  ## Examples
      main_item(parcel)
  """
  @spec main_item(t()) :: {{atom(), binary(), any(), binary()}, any()} | nil
  def main_item(%__MODULE__{data: items}) do
    Enum.find(items, fn
      {{:dialog_message, _, _, _}, %DialogMessage{}} -> true
      {{:room_message, _, _, _}, _} -> true
      _ -> false
    end)
  end

  def inject_next_index(%__MODULE__{data: items} = parcel) do
    case items do
      [{{:dialog_message, dkey, :next, msg_id}, %DialogMessage{} = msg}] ->
        next = Chat.Ordering.next({:dialog_message, dkey})
        %{parcel | data: [{{:dialog_message, dkey, next, msg_id}, msg}]}

      [
        {{:memo, _}, _} = m,
        {{:memo_index, _, _}, true} = i1,
        {{:memo_index, _, _}, true} = i2,
        {{:dialog_message, dkey, :next, msg_id}, %{type: :memo} = msg}
      ] ->
        next = Chat.Ordering.next({:dialog_message, dkey})
        %{parcel | data: [m, i1, i2, {{:dialog_message, dkey, next, msg_id}, msg}]}

      [
        {{:room_invite, _}, _} = ri,
        {{:room_invite_index, _, _} = i1, _},
        {{:room_invite_index, _, _} = i2, _},
        {{:dialog_message, dkey, :next, msg_id}, %{type: :room_invite} = msg}
      ] ->
        next = Chat.Ordering.next({:dialog_message, dkey})
        # TODO: room trace requires to know both room pub keys and room count
        room_trace = true
        # room_trace = Chat.RoomInviteIndex.room_trace(msg.room_pub_key, msg_id)

        %{
          parcel
          | data: [
              ri,
              {i1, room_trace},
              {i2, room_trace},
              {{:dialog_message, dkey, next, msg_id}, msg}
            ]
        }

      _ ->
        parcel
    end
  end

  def prepare_for_broadcast(%__MODULE__{data: items}) do
    case items do
      [{{:dialog_message, key, index, _}, %DialogMessage{type: :text} = msg}] ->
        {:new_dialog_message, key, {index, msg}}

      [
        {{:memo, _}, _},
        {{:memo_index, _, _}, true},
        {{:memo_index, _, _}, true},
        {{:dialog_message, key, index, _}, %DialogMessage{type: :memo} = msg}
      ] ->
        {:new_dialog_message, key, {index, msg}}

      [
        {{:room_invite, _}, _},
        {{:room_invite_index, _, _}, _},
        {{:room_invite_index, _, _}, _},
        {{:dialog_message, key, index, _}, %DialogMessage{type: :room_invite} = msg}
      ] ->
        {:new_dialog_message, key, {index, msg}}
    end
  end

  def data_items(%__MODULE__{data: data}), do: data

  defp new(list) do
    %__MODULE__{data: list}
  end

  defp sign(%__MODULE__{} = parcel, private_key) do
    sign =
      parcel
      |> Enigma.hash()
      |> Enigma.sign(private_key)

    %{parcel | sign: sign}
  end

  defp dialog_peer_keys(dialog_key) do
    dialog =
      Chat.Dialogs.Registry.find(dialog_key)

    [dialog.a_key, dialog.b_key]
  end

  @doc """
  Extracts the main message from a signed parcel as an {index, message} tuple.
  Works for any message type (room_message, dialog_message, etc.)

  This is a centralized extraction function that handles different message types uniformly,
  making it easier to work with parcels without duplicating extraction logic across modules.

  ## Parameters
  - parcel: A SignedParcel struct containing message data

  ## Returns
  - {index, message} tuple where index is the message index and message is the extracted message

  ## Raises
  - ArgumentError if the parcel does not contain a valid message

  ## Examples
      iex> extract_indexed_message(dialog_parcel)
      {123, %Chat.Dialogs.Message{type: :text, content: "Hello"}}

      iex> extract_indexed_message(room_parcel)
      {456, %Chat.Rooms.Message{type: :text, content: "Room message"}}
  """
  @spec extract_indexed_message(t()) :: {integer(), any()}
  def extract_indexed_message(%__MODULE__{data: data}) do
    # Extract based on message type pattern and transform in one step
    Enum.find_value(data, fn
      {{:dialog_message, _dialog_hash, index, _msg_id}, message} -> {index, message}
      {{:room_message, _room_key, index, _msg_id}, message} -> {index, message}
      _ -> false
    end) || raise ArgumentError, "Parcel does not contain a message"
  end

  @doc """
  Gets the type of the main message in the parcel (:dialog_message, :room_message, etc.)

  This is a centralized helper function that determines the message type in a parcel,
  simplifying type-specific operations on parcels.

  ## Parameters
  - parcel: A SignedParcel struct containing message data

  ## Returns
  - The message type as an atom (e.g., :dialog_message, :room_message)
  - nil if no recognized message type is found

  ## Examples
      iex> message_type(dialog_parcel)
      :dialog_message

      iex> message_type(room_parcel)
      :room_message

      iex> message_type(empty_parcel)
      nil
  """
  @spec message_type(t()) :: atom() | nil
  def message_type(%__MODULE__{data: data}) do
    Enum.find_value(data, fn {key, _} ->
      case key do
        {type, _, _, _} when type in [:dialog_message, :room_message] -> type
        _ -> false
      end
    end)
  end
end

defimpl Enigma.Hash.Protocol, for: Chat.SignedParcel do
  def to_iodata(parcel) do
    inspect(
      parcel.data,
      limit: :infinity,
      structs: false,
      custom_options: [sort_maps: true]
    )
  end
end
