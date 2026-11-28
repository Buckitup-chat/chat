defmodule Chat.Db.Scope.KeyScope.CargoInvites do
  @moduledoc """
  Cargo-room key scope: keys reachable by walking room invites from the invited users.

  Starts from the users invited into the cargo room, follows `:room_invite_index` edges
  between users (one step backward, two forward) and collects the dialogs, invite
  messages and invite records along the way.
  """

  @dialyzer {:no_opaque, keys: 3, traverse: 3}

  import Chat.Db.Scope.Utils

  @doc "Keys of dialogs and room invites reachable from `start_users` for the room `room_key`."
  def keys(snap, start_users, room_key) do
    room_key_hash = room_key |> Enigma.hash()

    full_invite_index =
      snap
      |> db_stream({:room_invite_index, 0, 0}, {:"room_invite_index\0", 0, 0})
      |> Stream.filter(&invite_like_in_room_hash?(&1, room_key_hash))
      |> Enum.reduce(Map.new(), fn
        {{:room_invite_index, user_key, invite_key}, value}, acc ->
          {list, trace} = Map.get(acc, invite_key, {[], value})
          Map.put(acc, invite_key, {[user_key | list], trace})

        _, acc ->
          acc
      end)
      |> Enum.reduce(Map.new(), fn
        {invite_key, {[a, b], trace}}, acc ->
          acc
          |> add_in_user_invite_index(a, b, {invite_key, trace})
          |> add_in_user_invite_index(b, a, {invite_key, trace})

        _, acc ->
          acc
      end)

    {_full_invite_index, traversed_keys, _source_users, _traversed_users} =
      {full_invite_index, MapSet.new(), start_users, MapSet.new()}
      |> traverse(snap, backward_messages?: true)
      |> traverse(snap)
      |> traverse(snap)

    traversed_keys
  end

  defp traverse(
         {full_invite_index, traversed_keys, source_users, traversed_users},
         snap,
         [backward_messages?: backward?] \\ [backward_messages?: false]
       ) do
    invite_pairs =
      full_invite_index
      |> Map.take(source_users |> MapSet.to_list())
      |> Enum.flat_map(fn {source_user, map} ->
        map |> Enum.map(fn {user, invite_keys} -> {source_user, user, invite_keys} end)
      end)

    destination_users =
      invite_pairs
      |> Enum.map(fn {_source_user, user, _invite_key} -> user end)
      |> MapSet.new()

    keys =
      invite_pairs
      |> Enum.flat_map(fn {source_user, user, invite_keys} ->
        traces =
          invite_keys
          |> MapSet.new(&elem(&1, 1))

        dialog_keys = generate_message_and_dialog_keys(source_user, user, backward?, traces, snap)

        if match?([_], dialog_keys),
          do: [],
          else: [
            dialog_keys,
            generate_invite_keys(source_user, user, invite_keys)
          ]
      end)
      |> List.flatten()
      |> MapSet.new()

    updated_keys = MapSet.union(traversed_keys, keys)
    new_traversed_users = MapSet.union(traversed_users, source_users)
    new_destination_users = MapSet.difference(destination_users, new_traversed_users)

    {full_invite_index, updated_keys, new_destination_users, new_traversed_users}
  end

  def invite_like_in_room_hash?(invite_keypair, room_key_hash) do
    case invite_keypair do
      {{:room_invite_index, _, _}, {bit_length, bits, _}} ->
        match?(
          <<^bits::bitstring-size(^bit_length), _::bitstring>>,
          room_key_hash
        )

      _ ->
        false
    end
  end

  defp invite_like_in_message_id_hash?(traces, message_id_hash) do
    traces
    |> Enum.any?(fn
      {_, _, hash} -> hash == message_id_hash
      _ -> false
    end)
  end

  defp generate_invite_keys(source_user, user, invite_keys) do
    invite_keys
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.flat_map(fn invite_key ->
      [
        {:room_invite, invite_key},
        {:room_invite_index, source_user, invite_key},
        {:room_invite_index, user, invite_key}
      ]
    end)
  end

  defp generate_message_and_dialog_keys(source_user, user, backward?, traces, snap) do
    dialog_key = dialog_key(source_user, user)

    dialog =
      snap
      |> db_stream({:dialogs, dialog_key}, {:dialogs, dialog_key})
      |> Enum.to_list()
      |> case do
        [{_, dialog}] -> dialog
        [{_, dialog} | _] -> dialog
      end

    snap
    |> db_stream({:dialog_message, dialog_key, 0, 0}, {:dialog_message, dialog_key, nil, 0})
    |> Stream.filter(fn {{:dialog_message, _, _, _}, msg} ->
      correct_direction? =
        (source_user == dialog.a_key and msg.is_a_to_b? and not backward?) or
          (source_user == dialog.a_key and not msg.is_a_to_b? and backward?) or
          (source_user == dialog.b_key and not msg.is_a_to_b? and not backward?) or
          (source_user == dialog.b_key and msg.is_a_to_b? and backward?)

      msg.type == :room_invite and
        correct_direction? and invite_like_in_message_id_hash?(traces, msg.id |> Enigma.hash())
    end)
    |> Enum.map(fn {key, _} -> key end)
    |> then(&[{:dialogs, dialog_key} | &1])
  catch
    _, _ -> []
  end

  defp dialog_key(user_a, user_b) do
    %Chat.Dialogs.Dialog{a_key: user_a, b_key: user_b} |> Enigma.hash()
  end

  defp add_in_user_invite_index(map, a, b, invite_key) do
    user_edges = Map.get(map, a, Map.new())
    invites_list = get_in(map, [a, b]) || []
    updated_user_edges = Map.put(user_edges, b, [invite_key | invites_list])
    Map.put(map, a, updated_user_edges)
  end
end
