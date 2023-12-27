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

  def get_invitation_participant(dialog, type, is_a_to_b) when type in [:sender, :recipient] do
    case type do
      :sender -> if(is_a_to_b, do: dialog.a_key, else: dialog.b_key)
      :recipient -> if(is_a_to_b, do: dialog.b_key, else: dialog.a_key)
    end
  end

  def fetch_dialog_by_key({snap, dialog_key}),
    do: CubDB.Snapshot.get(snap, {:dialogs, dialog_key}, {:dialogs, dialog_key})

  def get_messages_keys(messages),
    do:
      messages
      |> Stream.concat()
      |> Stream.map(&just_keys/1)

  def extract_dialogs_with_invitations(context, type, snap, [keys, dialog_keys] \\ [[], []])
      when type in [:checkpoints, :users] do
    dialog_keys = define_dialogs_keys(context, type, [keys, dialog_keys])
    invitation_category = define_invitation_category(context)
    context = Map.put(context, "#{invitation_category}_dialog_keys", dialog_keys)

    messages =
      dialog_keys |> get_dialog_binkeys() |> get_dialog_invitation_messages(snap)

    Map.put(context, "#{invitation_category}_dialogs", {dialog_keys, messages})
  end

  def union_set_dialog_keys(acc_keys, dialog_keys),
    do:
      acc_keys
      |> union_set(dialog_keys_union(dialog_keys))

  def put_invitation_dialogs(snap, context \\ %{}),
    do: Map.put(context, "dialogs", get_dialogs(snap))

  def put_invitations_sender_keys(context, type, snap, [step, keys] \\ [0, []]) do
    sender_keys =
      get_invitations_sender_keys(type, snap, context_invitations_messages(context, step))

    keys = if Enum.empty?(keys), do: sender_keys, else: sender_keys |> MapSet.difference(keys)

    Map.put(
      context,
      case step do
        0 -> "operators_keys"
        1 -> "nested_users_keys"
      end,
      keys
    )
  end

  def context_invitations_messages(context, step) do
    {_dialogs, messages} =
      if step == 0, do: context["checkpoints_dialogs"], else: context["operators_dialogs"]

    messages
  end

  def merge_dialogs_keys(messages_keys, acc_set, dialogs_keys) do
    messages_keys
    |> union_set_dialog_keys(dialogs_keys)
    |> union_set(acc_set)
  end

  def define_invitation_category(context) do
    case [
      Map.has_key?(context, "checkpoints_dialogs"),
      Map.has_key?(context, "operators_dialogs")
    ] do
      [false, false] -> :checkpoints
      [true, false] -> :operators
      _ -> :nested_users
    end
  end

  def define_dialogs_keys(context, type, [keys, dialog_keys]) do
    case define_invitation_category(context) do
      :checkpoints ->
        get_type_dialog_keys(type, context["dialogs"], [keys, dialog_keys])

      :operators ->
        case Map.fetch(context, "checkpoints_dialogs") do
          {:ok, {keys, _messages}} ->
            get_type_dialog_keys(type, context["dialogs"], [context["operators_keys"], keys])

          _ ->
            {:error, :not_found}
        end

      :nested_users ->
        case Map.fetch(context, "operators_dialogs") do
          {:ok, {keys, _messages}} ->
            get_type_dialog_keys(type, context["dialogs"], [context["nested_users_keys"], keys])

          _ ->
            {:error, :not_found}
        end
    end
  end

  def put_invitations_info(context) do
    [
      context["checkpoints_dialogs"],
      context["operators_dialogs"],
      context["nested_users_dialogs"]
    ]
    |> Enum.reduce(%{dialogs_keys: [], messages: []}, fn {keys, messages}, acc ->
      %{
        acc
        | dialogs_keys: acc.dialogs_keys ++ [keys],
          messages: acc.messages ++ [messages]
      }
    end)
    |> then(&Map.put(context, "invitations_info", &1))
  end

  def full_hadshake_keys(pub_keys, users_keys), do: pub_keys |> MapSet.union(users_keys)
end
