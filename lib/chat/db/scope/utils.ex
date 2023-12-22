defmodule Chat.Db.Scope.Utils do
  @moduledoc """
  Utils for db key scope
  """

  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Message

  def db_keys_stream(snap, min, max) do
    snap
    |> db_stream(min, max)
    |> Stream.map(&just_keys/1)
  end

  def db_stream(snap, min, max) do
    CubDB.Snapshot.select(snap, min_key: min, max_key: max)
  end

  def union_set(list, set) do
    list
    |> MapSet.new()
    |> MapSet.union(set)
  end

  def just_keys({k, _v}), do: k

  def get_dialogs(snap) do
    snap
    |> db_stream({:dialogs, 0}, {:"dialogs\0", 0})
    |> Enum.to_list()
    |> MapSet.new()
  end

  def get_just_dialog_keys(dialogs) do
    dialogs
    |> Stream.map(&just_keys/1)
    |> Enum.to_list()
    |> MapSet.new()
  end

  def get_type_dialog_keys(type, dialogs, [keys, exclude_dialog_keys]) do
    dialogs
    |> Stream.filter(fn {{:dialogs, dialog_key}, %Dialog{a_key: a_key, b_key: b_key}} ->
      (MapSet.member?(keys, a_key) or MapSet.member?(keys, b_key)) and
        case type do
          :users -> dialog_key not in exclude_dialog_keys
          :checkpoints -> true
        end
    end)
    |> get_just_dialog_keys()
  end

  def dialog_keys_union(list_of_keys),
    do: Enum.reduce(list_of_keys, MapSet.new(), &MapSet.union(&1, &2))

  def get_invitations_sender_keys(type, snap, invitation_messages) do
    invitation_messages
    |> Stream.map(fn {{:dialog_message, dialog_key, _, _},
                      %Message{is_a_to_b?: is_a_to_b} = _message} ->
      {snap, dialog_key}
      |> fetch_dialog_by_key()
      |> get_invitation_participant(type, is_a_to_b)
    end)
    |> MapSet.new()
  end

  def sender_invitation_condition(dialog, is_a_to_b),
    do: if(is_a_to_b, do: dialog.a_key, else: dialog.b_key)

  def recipient_invitation_condition(dialog, is_a_to_b),
    do: if(is_a_to_b, do: dialog.b_key, else: dialog.a_key)

  def get_dialog_binkeys(dialog_keys),
    do: dialog_keys |> Enum.map(fn {:dialogs, dialog_key} -> dialog_key end) |> MapSet.new()

  def get_dialog_invitation_messages(dialog_binkeys, snap) do
    dialog_binkeys
    |> Stream.map(fn dialog_key ->
      {{:dialog_message, dialog_key, 0, 0}, {:dialog_message, dialog_key, nil, nil}}
    end)
    |> Enum.map(fn {min, max} = _range ->
      snap
      |> db_stream(min, max)
      |> Stream.filter(&match?({_, %Message{type: :room_invite}}, &1))
    end)
    |> Stream.concat()
  end

  defp get_invitation_participant(dialog, type, is_a_to_b) when type in [:sender, :recipient] do
    case type do
      :sender -> if(is_a_to_b, do: dialog.a_key, else: dialog.b_key)
      :recipient -> if(is_a_to_b, do: dialog.b_key, else: dialog.a_key)
    end
  end

  defp fetch_dialog_by_key({snap, dialog_key}),
    do:
      snap
      |> db_stream({:dialogs, dialog_key}, {:"dialogs\0", dialog_key})
      |> Enum.to_list()
      |> List.first()
      |> then(fn {_, dialog} -> dialog end)
end
