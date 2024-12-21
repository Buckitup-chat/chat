defmodule Chat.SignedParcel do
  @moduledoc """
  A package of message with attachment and indexes.
  Signed by author. So can be checked for integrity.
  """

  alias Chat.Dialogs.DialogMessaging

  defstruct data: [], sign: ""

  def wrap_dialog_message(message, dialog, me) do
    type = Chat.DryStorable.type(message)
    {content, data_list} = Chat.DryStorable.to_parcel(message)

    msg = DialogMessaging.content_to_message(content, me, dialog, type: type)
    msg_key = DialogMessaging.msg_key(dialog, :next, msg.id)

    Enum.reduce(data_list, [{msg_key, msg}], fn
      {{:memo, key}, _} = data, acc ->
        extra = Chat.MemoIndex.pack(dialog, key)
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
      [{{:dialog_message, dialog_key, _, _}, %Chat.Dialogs.Message{type: :text}}] ->
        public_key in dialog_peer_keys(dialog_key)

      [
        {{:memo, _}, _},
        {{:memo_index, some_pkey, _}, true},
        {{:memo_index, other_okey, _}, true},
        {{:dialog_message, dialog_key, _, _}, %Chat.Dialogs.Message{type: :memo}}
      ] ->
        cond do
          some_pkey != public_key and other_okey != public_key -> false
          peers = dialog_peer_keys(dialog_key) -> some_pkey in peers and other_okey in peers
        end
    end
  end

  def main_item(%__MODULE__{data: items}) do
    case items do
      [{{:dialog_message, _, _, _}, %Chat.Dialogs.Message{type: :text}} = x] ->
        x

      [
        {{:memo, _}, _},
        {{:memo_index, _, _}, true},
        {{:memo_index, _, _}, true},
        {{:dialog_message, _, _, _}, %Chat.Dialogs.Message{type: :memo}} = x
      ] ->
        x
    end
  end

  def inject_next_index(%__MODULE__{data: items} = parcel) do
    case items do
      [{{:dialog_message, dkey, :next, msg_id}, %Chat.Dialogs.Message{} = msg}] ->
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

      x ->
        x
    end
  end

  def prepare_for_broadcast(%__MODULE__{data: items}) do
    case items do
      [{{:dialog_message, key, index, _}, %Chat.Dialogs.Message{type: :text} = msg}] ->
        {:new_dialog_message, key, {index, msg}}

      [
        {{:memo, _}, _},
        {{:memo_index, _, _}, true},
        {{:memo_index, _, _}, true},
        {{:dialog_message, key, index, _}, %Chat.Dialogs.Message{type: :memo} = msg}
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
