defmodule Chat.Db.Scope.InvitationLevel do
  @moduledoc """
  Process cargo room invitations
  """

  import Chat.Db.Scope.Utils
  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Message

  @invitations_depth 4

  def build_initial_context(snap, pub_keys) do
    %{}
    |> put_room_invitations_content(snap, nil)
    |> put_invitations_keymap()
    |> put_operators_keys(pub_keys)
    |> put_initial_invites_queque(snap, pub_keys)
    |> put_invitations_messages(snap)
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

  def execute_handshake_cycle(context) do
    if is_last_handshake_cycle?(context) do
      context
    else
      context
      |> get_current_queue_senders()
      |> fetch_cycle_invites(context)
      |> put_invitations_queue(context)
      |> remove_queued_invitations_messages()
      |> execute_handshake_cycle()
    end
  end

  defp put_room_invitations_content(context, snap, keys) do
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
         {invite_key, dialog_key, is_a_to_b, message_id, %{a_key: a_key, b_key: b_key} = _message}
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
      dialog_message: {:dialog_message, dialog_key, nil, message_id}
    }
  end

  defp fetch_cycle_invites(sender_keys, %{invitations_messages: invitations_messages} = _context) do
    invitations_messages
    |> Enum.filter(fn {_, _, is_a_to_b, _, %{a_key: user1_key, b_key: user2_key}} ->
      case is_a_to_b do
        true -> MapSet.member?(sender_keys, user1_key)
        false -> MapSet.member?(sender_keys, user2_key)
      end
    end)
  end

  defp get_messages_sender_keys(messages, type) do
    messages
    |> Enum.map(fn {_, _dialog_key, is_a_to_b, _, %{a_key: a_key, b_key: b_key}} ->
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

  defp put_invitations_queue(invitations, context),
    do: context |> Map.put(:invitations_queue, [invitations])

  defp remove_queued_invitations_messages(
         %{invitations_queue: _queue, invitations_messages: []} = context
       ),
       # coveralls-ignore-next-line
       do: context

  defp remove_queued_invitations_messages(
         %{invitations_queue: queue, invitations_messages: messages} = context
       ) do
    %{
      context
      | invitations_messages:
          Enum.reject(messages, fn value ->
            value in List.flatten(queue)
          end)
    }
  end

  defp clear_context_preparation(%{room_invites: _, room_invite_indexes: _} = context),
    do: Map.drop(context, [:room_invites, :room_invite_indexes, :invitations_keymap])

  defp put_invitations_messages(
         %{invitations_keymap: keymap, invitations_queue: queue, operators_keys: operators} =
           context,
         snap
       ) do
    # TODO: process invitations based on queue and keymap
    # Now invitations queue contain invite messages to checkoints from operators
    # Next need to take operators keys and find to who they send invites exclude pubkeys
    # Base on that fetch and build invitations messages start from operators and each next user in keymap

    context
  end

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
    operators_keys =
      keymap
      |> Enum.map(fn {_key, [user_1, user_2]} ->
        case {user_1 in pub_keys, user_2 in pub_keys} do
          {true, false} -> user_2
          {false, true} -> user_1
          _ -> nil
        end
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
         %{invitations_queue: queue, invitations_messages: messages} = context
       ),
       do:
         Enum.empty?(messages) or not is_related_invitations_exists?(context) or
           length(queue) == @invitations_depth

  defp is_related_invitations_exists?(
         %{invitations_messages: messages, invitations_queue: _queue} = context
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
        operators

      _ ->
        queue
        |> List.first()
        |> get_messages_sender_keys(:users)
    end
  end

  defp get_current_queue_senders(%{invitations_queue: queue}) do
    queue
    |> List.first()
    |> get_messages_sender_keys(:operators)
  end

  defp is_recipient_exists?(sender_keys, messages) do
    messages
    |> Enum.any?(fn {_, _, is_a_to_b, _, %{a_key: a_key, b_key: b_key}} ->
      case is_a_to_b do
        true -> MapSet.member?(sender_keys, a_key)
        false -> MapSet.member?(sender_keys, b_key)
      end
    end)
  end

  defp define_sender_key(is_a_to_b, :operators, {a_key, b_key}) do
    case is_a_to_b do
      true -> a_key
      false -> b_key
    end
  end

  defp define_sender_key(is_a_to_b, :users, {a_key, b_key}) do
    case is_a_to_b do
      true -> b_key
      false -> a_key
    end
  end

  defp put_initial_invites_queque(
         %{invitations_keymap: keymap, operators_keys: operators} = context,
         snap,
         pub_keys
       ) do
    keymap
    |> filter_root_keymap(pub_keys, operators)
    |> Enum.map(fn {invite_key, [a_key, b_key]} ->
      dialog_key = build_dialog_key({a_key, b_key})

      invite_message =
        dialog_key
        |> get_invite_messages_by_dialog_key(snap)
        |> Enum.at(0)

      {_, %Message{is_a_to_b?: is_a_to_b, id: message_id}} = invite_message

      {
        invite_key,
        dialog_key,
        is_a_to_b,
        message_id,
        # TODO: preset right keys by direction
        %{a_key: a_key, b_key: b_key}
      }
    end)
    |> then(&Map.put_new(context, :invitations_queue, &1))
  end

  defp get_invite_messages_by_dialog_key(dialog_key, snap) do
    snap
    |> db_stream(
      {:dialog_message, dialog_key, 0, 0},
      {:dialog_message, dialog_key, nil, nil}
    )
    |> Stream.filter(&match?({_, %Message{type: :room_invite}}, &1))
  end

  defp filter_root_keymap(keymap, pub_keys, operators) do
    keymap
    |> Enum.filter(fn {invite_key, [a_key, b_key]} ->
      is_root_key?([a_key, b_key], pub_keys, operators)
    end)
  end

  defp is_root_key?([a_key, b_key], pub_keys, operators),
    do: Enum.any?([a_key, b_key], fn key -> key in pub_keys or key in operators end)

  defp build_dialog_key({a_key, b_key}), do: %Dialog{a_key: a_key, b_key: b_key} |> Enigma.hash()
end
