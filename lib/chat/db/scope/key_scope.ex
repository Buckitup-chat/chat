defmodule Chat.Db.Scope.KeyScope do
  @moduledoc """
  Builds db keys accessible by keys_list
  """

  import Chat.Db.Scope.Utils
  import Chat.Db.Scope.InvitationLevel
  alias Chat.Dialogs.Dialog

  def get_keys(db, pub_keys_list) do
    pub_keys = MapSet.new(pub_keys_list)

    CubDB.with_snapshot(db, fn snap ->
      MapSet.new()
      |> add_full_users(snap)
      |> add_dialogs(snap, pub_keys)
      |> add_rooms(snap, pub_keys)
      |> add_content(snap, pub_keys)
    end)
  end

  def get_cargo_keys(db, room_pub_key, invites_to_pub_keys) do
    room_key = MapSet.new([room_pub_key])
    invited_keys = MapSet.new(invites_to_pub_keys)

    CubDB.with_snapshot(db, fn snap ->
      MapSet.new()
      |> add_rooms(snap, room_key)
      |> add_content(snap, room_key)
      |> add_cargo_invites(snap, invited_keys, room_pub_key)
    end)
  end

  defp add_full_users(acc_set, snap) do
    snap
    |> db_keys_stream({:users, 0}, {:"users\0", 0})
    |> union_set(acc_set)
  end

  defp add_dialogs(acc_set, snap, pub_keys) do
    dialog_keys =
      snap
      |> db_stream({:dialogs, 0}, {:"dialogs\0", 0})
      |> Stream.filter(fn {_full_dilaog_key, %Dialog{a_key: a_key, b_key: b_key}} ->
        MapSet.member?(pub_keys, a_key) or MapSet.member?(pub_keys, b_key)
      end)
      |> Stream.map(fn {dialog_key, _dialog} -> dialog_key end)
      |> MapSet.new()

    dialog_binkeys =
      dialog_keys
      |> Enum.map(fn {:dialogs, dialog_key} -> dialog_key end)
      |> MapSet.new()

    snap
    |> db_keys_stream({:dialog_message, 0, 0, 0}, {:"dialog_message\0", 0, 0, 0})
    |> Stream.filter(fn {:dialog_message, key, _, _} ->
      MapSet.member?(dialog_binkeys, key)
    end)
    |> union_set(dialog_keys)
    |> union_set(acc_set)
  end

  defp add_rooms(acc_set, snap, pub_keys) do
    with_rooms =
      snap
      |> db_keys_stream({:rooms, 0}, {:"rooms\0", 0})
      |> Stream.filter(fn {:rooms, key} ->
        MapSet.member?(pub_keys, key)
      end)
      |> union_set(acc_set)

    snap
    |> db_keys_stream({:room_message, 0, 0, 0}, {:"room_message\0", 0, 0, 0})
    |> Stream.filter(fn {:room_message, room_key, _, _} ->
      MapSet.member?(pub_keys, room_key)
    end)
    |> union_set(with_rooms)
  end

  defp add_content(acc_set, snap, pub_keys) do
    [file_index, file_keys, files] =
      fetch_index_and_records(
        snap,
        pub_keys,
        "file",
        min_key: {:file_index, 0, 0, 0},
        max_key: {:"file_index\0", 0, 0, 0},
        reader_hash_getter: fn {:file_index, reader_key, _file_key, _message_id} ->
          reader_key
        end,
        record_key_getter: fn {:file_index, _reader_key, file_key, _message_id} -> file_key end
      )

    chunk_keys =
      snap
      |> db_keys_stream(
        {:chunk_key, {:file_chunk, 0, 0, 0}},
        {:chunk_key, {:"file_chunk\0", 0, 0, 0}}
      )
      |> Stream.filter(fn {:chunk_key, {:file_chunk, file_key, _chunk_start, _chunk_end}} ->
        MapSet.member?(file_keys, file_key)
      end)
      |> MapSet.new()

    file_chunks =
      chunk_keys
      |> Enum.map(fn {:chunk_key, file_chunk_key} -> file_chunk_key end)
      |> MapSet.new()

    [memo_index, _memo_keys, memos] =
      fetch_index_and_records(
        snap,
        pub_keys,
        "memo",
        min_key: {:memo_index, 0, 0},
        max_key: {:"memo_index\0", 0, 0},
        reader_hash_getter: fn {:memo_index, reader_key, _memo_key} -> reader_key end,
        record_key_getter: fn {:memo_index, _reader_key, memo_key} -> memo_key end
      )

    [room_invite_index, _room_invite_keys, room_invites] =
      fetch_index_and_records(
        snap,
        pub_keys,
        "room_invite",
        min_key: {:room_invite_index, 0, 0},
        max_key: {:"room_invite_index\0", 0, 0},
        reader_hash_getter: fn {:room_invite_index, reader_key, _invite_key} -> reader_key end,
        record_key_getter: fn {:room_invite_index, _reader_key, invite_key} -> invite_key end
      )

    acc_set
    |> union_set(chunk_keys)
    |> union_set(file_index)
    |> union_set(file_chunks)
    |> union_set(files)
    |> union_set(memo_index)
    |> union_set(memos)
    |> union_set(room_invite_index)
    |> union_set(room_invites)
  end

  defp add_cargo_invites(acc_set, snap, pub_keys, room_key) do
    build_user_invite_indexes(snap, pub_keys, room_key)
    |> MapSet.union(acc_set)
  end

  defp build_user_invite_indexes(snap, start_users, room_key) do
    room_key_hash = room_key |> Enigma.hash()

    full_invite_index =
      snap
      |> db_stream({:room_invite_index, 0, 0}, {:"room_invite_index\0", 0, 0})
      |> Stream.filter(&invite_like_in_room_hash?(&1, room_key_hash))
      |> Enum.reduce(Map.new(), fn
        {{:room_invite_index, user_key, invite_key}, _}, acc ->
          Map.put(acc, invite_key, [user_key | Map.get(acc, invite_key, [])])

        _, acc ->
          acc
      end)
      |> Enum.reduce(Map.new(), fn
        {invite_key, [a, b]}, acc ->
          acc
          |> add_in_user_invite_index(a, b, invite_key)
          |> add_in_user_invite_index(b, a, invite_key)

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
        dialog_keys = generate_message_and_dialog_keys(source_user, user, backward?, snap)

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

  defp invite_like_in_room_hash?(invite_keypair, room_key_hash)

  defp invite_like_in_room_hash?({_, {bit_length, bitstring}}, room_key_hash) do
    match?(
      <<^bitstring::bitstring-size(bit_length), _::bitstring>>,
      room_key_hash
    )
  end

  defp invite_like_in_room_hash?({_, true}, _), do: true
  defp invite_like_in_room_hash?(_, _), do: false

  defp generate_invite_keys(source_user, user, invite_keys) do
    invite_keys
    |> Enum.uniq()
    |> Enum.flat_map(fn invite_key ->
      [
        {:room_invite, invite_key},
        {:room_invite_index, source_user, invite_key},
        {:room_invite_index, user, invite_key}
      ]
    end)
  end

  defp generate_message_and_dialog_keys(source_user, user, backward?, snap) do
    dialog_key = dialog_key(source_user, user)

    [{_, dialog}] =
      snap |> db_stream({:dialogs, dialog_key}, {:dialogs, dialog_key}) |> Enum.to_list()

    snap
    |> db_stream({:dialog_message, dialog_key, 0, 0}, {:dialog_message, dialog_key, nil, 0})
    |> Stream.filter(fn {{:dialog_message, _, _, _}, msg} ->
      correct_direction? =
        (source_user == dialog.a_key and msg.is_a_to_b? and not backward?) or
          (source_user == dialog.a_key and not msg.is_a_to_b? and backward?) or
          (source_user == dialog.b_key and not msg.is_a_to_b? and not backward?) or
          (source_user == dialog.b_key and msg.is_a_to_b? and backward?)

      msg.type == :room_invite and
        correct_direction?
    end)
    |> Enum.map(fn {key, _} -> key end)
    |> then(&[{:dialogs, dialog_key} | &1])
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
