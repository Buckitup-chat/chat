defmodule Chat.SignedParcel.Delivery do
  @moduledoc """
  Server-side steps for a received `Chat.SignedParcel`, matched on the known parcel shapes
  (text, memo, room invite; dialog and room messages):

  - `scope_valid?/2` — the signer is allowed to write every item of the parcel
  - `inject_next_index/1` — replaces the `:next` placeholder with the next dialog index
  - `prepare_for_broadcast/1` — the PubSub message announcing the stored parcel
  """

  alias Chat.Dialogs.Message, as: DialogMessage
  alias Chat.Rooms.Message, as: RoomMessage
  alias Chat.SignedParcel

  def scope_valid?(%SignedParcel{data: items}, public_key) do
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

  def inject_next_index(%SignedParcel{data: items} = parcel) do
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

  def prepare_for_broadcast(%SignedParcel{data: items}) do
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

  defp dialog_peer_keys(dialog_key) do
    dialog =
      Chat.Dialogs.Registry.find(dialog_key)

    [dialog.a_key, dialog.b_key]
  end
end
