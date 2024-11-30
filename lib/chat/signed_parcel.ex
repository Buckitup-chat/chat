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
