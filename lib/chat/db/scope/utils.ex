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
          :user -> dialog_key not in exclude_dialog_keys
          :checkpoints -> true
        end
    end)
    |> get_just_dialog_keys()
  end

  def dialog_keys_union(list_of_keys),
    do: Enum.reduce(list_of_keys, MapSet.new(), &MapSet.union(&1, &2))

  def get_invitation_sender_key(type, dialogs, invitation_messages) do
    invitation_messages
    |> Stream.map(fn {{:dialog_message, dialog_key, _, _},
                      %Message{is_a_to_b?: is_a_to_b} = _message} ->
      dialogs
      |> Enum.find(fn {{_, key}, _} ->
        key == dialog_key
      end)
      |> elem(1)
      |> then(
        &case type do
          :sender -> sender_invitation_condition(&1, is_a_to_b)
          :recipient -> recipient_invitation_condition(&1, is_a_to_b)
        end
      )
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
    snap
    |> db_stream({:dialog_message, 0, 0, 0}, {:"dialog_message\0", 0, 0, 0})
    |> Stream.filter(fn {{:dialog_message, key, _, _}, %Message{type: type}} ->
      type == :room_invite and MapSet.member?(dialog_binkeys, key)
    end)
  end

  # TODO: correct this function to work in next commit

  # def get_dialog_invitation_messages(dialog_binkeys, snap) do
  #   dialog_binkeys
  #   |> Stream.map(fn dialog_key ->
  #     {{:dialog_message, dialog_key, 0, 0}, {:dialog_message, dialog_key, nil, nil}}
  #   end)
  #   |> Stream.map(fn {min, max} = _range ->
  #     snap
  #     |> db_stream(min, max)
  #     |> Stream.filter(&match?({_, %Message{type: :room_invite}}, &1))
  #   end)
  # end
end
