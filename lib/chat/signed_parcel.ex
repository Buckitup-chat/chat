defmodule Chat.SignedParcel do
  @moduledoc """
  A package of message with attachment and indexes.
  Signed by author. So can be checked for integrity.
  """

  alias Chat.Dialogs.DialogMessaging
  alias Chat.Dialogs.Message, as: DialogMessage

  defstruct data: [], sign: ""

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
    end
  end

  def main_item(%__MODULE__{data: items}) do
    case items do
      [{{:dialog_message, _, _, _}, %DialogMessage{type: :text}} = x] ->
        x

      [
        {{:memo, _}, _},
        {{:memo_index, _, _}, true},
        {{:memo_index, _, _}, true},
        {{:dialog_message, _, _, _}, %DialogMessage{type: :memo}} = x
      ] ->
        x

      [
        {{:room_invite, _}, _},
        {{:room_invite_index, _, _}, _},
        {{:room_invite_index, _, _}, _},
        {{:dialog_message, _, _, _}, %DialogMessage{type: :room_invite}} = x
      ] ->
        x
    end
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
