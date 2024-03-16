defmodule Chat.Db.Scope.InvitationLevel do
  @moduledoc """
  Process cargo room invitations
  """
  import Chat.Db.Scope.Utils

  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Message

  @invitations_depth 4

  def build_initial_context(snap, pub_keys) do
    %{snap: snap}
    |> put_room_invitations_content(nil)
    |> put_invitations_keymap()
    |> put_operators_keys(pub_keys)
    |> put_initial_invites_queue(pub_keys)
    |> remove_queued_invitations_keymap()
    |> clear_context_preparation()
  end

  def process_invitation_groups(%{invitations_queue: invitations_queue} = _context) do
    invitations_queue
    |> Enum.reduce(
      %{
        dialogs_keys: MapSet.new(),
        room_invite_indexes: MapSet.new(),
        room_invites: MapSet.new(),
        dialog_messages: MapSet.new()
      },
      &process_invitation_group(&1, &2)
    )
  end

  def update_acc_set(consumed_keys, acc_set) do
    acc_set
    |> union_set(consumed_keys.dialog_messages)
    |> union_set(consumed_keys.dialogs_keys)
    |> union_set(consumed_keys.room_invite_indexes)
    |> union_set(consumed_keys.room_invites)
  end

  def fetch_index_and_records(snap, pub_keys, record_name, opts) do
    reader_hash_getter = opts[:reader_hash_getter]
    record_key_getter = opts[:record_key_getter]

    index =
      snap
      |> db_keys_stream(opts[:min_key], opts[:max_key])
      |> filter_invitations_indexes(reader_hash_getter, pub_keys)
      |> MapSet.new()

    keys =
      index
      |> Enum.map(&record_key_getter.(&1))
      |> MapSet.new()

    records =
      snap
      |> db_keys_stream({:"#{record_name}", 0}, {:"#{record_name}\0", 0})
      |> filter_invitations_records(keys)
      |> MapSet.new()

    [index, keys, records]
  end

  def execute_handshake_cycle(
        %{invitations_keymap: _keymap, invitations_queue: _queue, operators_keys: _operators} =
          context
      ) do
    if is_last_handshake_cycle?(context) do
      context
    else
      context
      |> get_current_queue_senders()
      |> fetch_cycle_invites(context)
      |> put_invitations_queue(context)
      |> remove_queued_invitations_keymap()
      |> execute_handshake_cycle()
    end
  end

  defp put_room_invitations_content(%{snap: snap} = context, keys) do
    [room_invite_index, _room_invite_keys, room_invites] =
      snap
      |> fetch_index_and_records(
        keys,
        "room_invite",
        min_key: {:room_invite_index, 0, 0},
        max_key: {:"room_invite_index\0", 0, 0},
        record_key_getter: fn {:room_invite_index, _reader_key, invite_key} -> invite_key end
      )

    Map.merge(context, %{room_invite_indexes: room_invite_index, room_invites: room_invites})
  end

  defp process_invitation_group(invitation_group, acc) do
    group_data =
      invitation_group
      |> Enum.map(&map_invitation_data(&1))
      |> MapSet.new()

    %{
      acc
      | dialogs_keys: union_set_acc(acc.dialogs_keys, group_data, &Map.get(&1, :dialog_key)),
        room_invite_indexes:
          union_set_acc(acc.room_invite_indexes, group_data, &Map.get(&1, :room_invite_index)),
        room_invites: union_set_acc(acc.room_invites, group_data, &Map.get(&1, :invite_key)),
        dialog_messages:
          union_set_acc(acc.dialog_messages, group_data, &Map.get(&1, :dialog_message))
    }
  end

  defp map_invitation_data(
         {invite_key, dialog_key, is_a_to_b, message_index, message_id,
          %{a_key: a_key, b_key: b_key} = _message}
       ) do
    %{
      dialog_key: {:dialogs, dialog_key},
      room_invite_index:
        {:room_invite_index,
         case is_a_to_b do
           true -> b_key
           false -> a_key
         end, invite_key},
      invite_key: {:room_invite, invite_key},
      dialog_message: {:dialog_message, dialog_key, message_index, message_id}
    }
  end

  defp fetch_cycle_invites(sender_keys, %{snap: snap, invitations_keymap: keymap} = _context) do
    keymap
    |> Enum.filter(fn
      {_invite_key, [user1_key, user2_key]} ->
        MapSet.member?(sender_keys, user1_key) or MapSet.member?(sender_keys, user2_key)

      _ ->
        false
    end)
    |> compose_invitations_messages(sender_keys, snap)
  end

  defp compose_invitations_messages(messages, sender_keys, snap) do
    messages
    |> Enum.flat_map(&compose_invite_message(&1, snap))
    |> reject_non_sender_messages(sender_keys)
  end

  defp compose_invite_message({invite_key, [first_key, second_key]} = invite, snap) do
    dialog_key = build_dialog_key({first_key, second_key})

    dialog_key
    |> get_invite_messages_by_dialog_key(snap)
    |> Enum.map(fn {{:dialog_message, ^dialog_key, msg_index, msg_id},
                    %Message{is_a_to_b?: is_a_to_b}} ->
      %Dialog{a_key: a_key, b_key: b_key} = Chat.Db.get({:dialogs, dialog_key})

      {
        invite_key,
        dialog_key,
        is_a_to_b,
        msg_index,
        msg_id,
        %{a_key: a_key, b_key: b_key}
      }
    end)
  rescue
    _ -> [{:error, invite}]
  end

  defp reject_non_sender_messages(messages, sender_keys) do
    messages
    |> Enum.reject(fn
      {_key, _dialog_key, true, _message_index, _message_id, %{a_key: a_key}} ->
        a_key not in sender_keys

      {_key, _dialog_key, _, _message_index, _message_id, %{b_key: b_key}} ->
        b_key not in sender_keys
    end)
  end

  defp get_messages_sender_keys(messages, type) do
    messages
    |> Enum.map(fn {_, _dialog_key, is_a_to_b, _, _, %{a_key: a_key, b_key: b_key}} ->
      define_sender_key(is_a_to_b, type, {a_key, b_key})
    end)
    |> MapSet.new()
  end

  # coveralls-ignore-next-line
  defp put_invitations_queue([], context), do: context

  defp put_invitations_queue(invitations, %{invitations_queue: queue} = context),
    do:
      Map.put(
        context,
        :invitations_queue,
        [invitations | queue]
      )

  defp remove_queued_invitations_keymap(
         %{invitations_queue: queue, invitations_keymap: keymap} = context
       ) do
    queued_invites = get_queued_invites_keys(queue)

    %{
      context
      | invitations_keymap:
          Enum.reject(keymap, fn {key, _} ->
            key in queued_invites
          end)
    }
  end

  defp clear_context_preparation(%{room_invites: _, room_invite_indexes: _} = context),
    do: Map.drop(context, [:room_invites, :room_invite_indexes])

  defp put_invitations_keymap(context) do
    {room_invites, room_invite_indexes} = {context.room_invites, context.room_invite_indexes}

    keymap =
      Enum.reduce(room_invites, %{}, fn {_, invite_key}, acc ->
        users =
          room_invite_indexes
          |> MapSet.to_list()
          |> Enum.filter(&(extract_invite_key(&1) == invite_key))
          |> Enum.map(&elem(&1, 1))

        Map.put(acc, invite_key, users)
      end)

    Map.put(context, :invitations_keymap, keymap)
  end

  defp put_operators_keys(%{invitations_keymap: keymap} = context, pub_keys) do
    keymap
    |> Enum.map(fn
      {_key, [user_1, user_2]} ->
        cond do
          user_1 in pub_keys and user_2 not in pub_keys -> user_2
          user_2 in pub_keys and user_1 not in pub_keys -> user_1
          true -> nil
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> then(&Map.put(context, :operators_keys, &1))
  end

  defp union_set_acc(set_acc, group_data, key_extractor) do
    group_data
    |> Enum.map(&key_extractor.(&1))
    |> union_set(set_acc)
  end

  defp extract_invite_key({:room_invite_index, _, invite_key}), do: invite_key

  defp filter_invitations_indexes(invitations, _reader_hash_getter, nil), do: invitations

  defp filter_invitations_indexes(invitations, reader_hash_getter, keys) do
    Stream.filter(invitations, fn key ->
      reader_hash = reader_hash_getter.(key)
      MapSet.member?(keys, reader_hash)
    end)
  end

  defp filter_invitations_records(invitations, keys) do
    Stream.filter(invitations, fn {_record_name, record_key} ->
      MapSet.member?(keys, record_key)
    end)
  end

  defp is_last_handshake_cycle?(
         %{invitations_queue: queue, invitations_keymap: messages} = context
       ),
       do:
         Enum.empty?(messages) or not is_related_invitations_exists?(context) or
           length(queue) == @invitations_depth

  defp is_related_invitations_exists?(
         %{invitations_keymap: messages, invitations_queue: _queue} = context
       ) do
    context
    |> get_current_queue_senders()
    |> is_recipient_exists?(messages)
  end

  defp get_current_queue_senders(
         %{invitations_queue: queue, operators_keys: operators} = _context
       ) do
    case length(queue) do
      1 ->
        operators |> MapSet.new()

      _ ->
        queue
        |> List.first()
        |> get_messages_sender_keys(:users)
    end
  end

  defp is_recipient_exists?(sender_keys, messages) do
    messages
    |> Enum.any?(fn
      {_invite_key, [user_1, user_2]} ->
        MapSet.member?(sender_keys, user_1) or MapSet.member?(sender_keys, user_2)

      _ ->
        false
    end)
  end

  defp define_sender_key(is_a_to_b, :users, {a_key, b_key}) do
    case is_a_to_b do
      true -> b_key
      false -> a_key
    end
  end

  defp put_initial_invites_queue(
         %{snap: snap, invitations_keymap: keymap, operators_keys: operators} = context,
         pub_keys
       ) do
    keymap
    |> filter_root_keymap(pub_keys)
    |> compose_invitations_messages(operators, snap)
    |> then(&Map.put_new(context, :invitations_queue, [&1]))
  end

  defp get_invite_messages_by_dialog_key(dialog_key, snap) do
    snap
    |> db_stream(
      {:dialog_message, dialog_key, 0, 0},
      {:dialog_message, dialog_key, nil, nil}
    )
    |> Stream.filter(&match?({_, %Message{type: :room_invite}}, &1))
  end

  defp filter_root_keymap(keymap, pub_keys) do
    keymap
    |> Enum.filter(fn
      {_invite_key, [a_key, b_key]} -> is_root_key?([a_key, b_key], pub_keys)
      _ -> false
    end)
  end

  defp is_root_key?([a_key, b_key], pub_keys),
    do: Enum.any?([a_key, b_key], fn key -> key in pub_keys end)

  defp build_dialog_key({a_key, b_key}), do: %Dialog{a_key: a_key, b_key: b_key} |> Enigma.hash()

  defp get_queued_invites_keys(queue),
    do: queue |> List.flatten() |> Enum.map(fn {invite_key, _, _, _, _, _} -> invite_key end)
end
