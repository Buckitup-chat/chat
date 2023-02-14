defmodule Chat.Db.Scope.KeyScope do
  @moduledoc """
  Builds db keys accessible by keys_list
  """

  alias Chat.Utils

  def get_keys(db, pub_keys_list) do
    hashes = hash_pubkeys(pub_keys_list)

    CubDB.with_snapshot(db, fn snap ->
      MapSet.new()
      |> add_full_users(snap)
      |> add_dialogs(snap, hashes)
      |> add_rooms(snap, hashes)
      |> add_content(snap, hashes)
      |> MapSet.to_list()
    end)
  end

  defp add_full_users(acc_set, snap) do
    snap
    |> db_keys_stream({:users, 0}, {:"users\0", 0})
    |> union_set(acc_set)
  end

  defp add_dialogs(acc_set, snap, {_binhashes, hashes}) do
    dialog_keys =
      snap
      |> db_keys_stream({:dialogs, 0}, {:"dialogs\0", 0})
      |> Stream.filter(fn {:dialogs, <<one::binary-size(64), other::binary-size(64)>>} ->
        MapSet.member?(hashes, one) or MapSet.member?(hashes, other)
      end)
      |> MapSet.new()

    dialog_binhashes =
      dialog_keys
      |> Enum.map(fn {:dialogs, hash} ->
        hash
        |> Utils.hash()
        |> Utils.binhash()
      end)
      |> MapSet.new()

    snap
    |> db_keys_stream({:dialog_message, 0, 0, 0}, {:"dialog_message\0", 0, 0, 0})
    |> Stream.filter(fn {:dialog_message, binhash, _, _} ->
      MapSet.member?(dialog_binhashes, binhash)
    end)
    |> union_set(dialog_keys)
    |> union_set(acc_set)
  end

  defp add_rooms(acc_set, snap, {binhashes, hashes}) do
    with_rooms =
      snap
      |> db_keys_stream({:rooms, 0}, {:"rooms\0", 0})
      |> Stream.filter(fn {:rooms, hash} ->
        MapSet.member?(hashes, hash)
      end)
      |> union_set(acc_set)

    snap
    |> db_keys_stream({:room_message, 0, 0, 0}, {:"room_message\0", 0, 0, 0})
    |> Stream.filter(fn {:room_message, room_binhash, _, _} ->
      MapSet.member?(binhashes, room_binhash)
    end)
    |> union_set(with_rooms)
  end

  defp add_content(acc_set, snap, {_, hashes}) do
    file_index =
      snap
      |> db_keys_stream({:file_index, 0, 0, 0}, {:"file_index\0", 0, 0, 0})
      |> Stream.filter(fn {:file_index, reader_hash, _file_key, _message_id} ->
        MapSet.member?(hashes, reader_hash)
      end)
      |> MapSet.new()

    file_keys =
      file_index
      |> Enum.map(fn {:file_index, _reader_hash, file_key, _message_id} -> file_key end)
      |> MapSet.new()

    file_chunks =
      snap
      |> db_keys_stream({:file_chunk, 0, 0, 0}, {:"file_chunk\0", 0, 0, 0})
      |> Stream.filter(fn {:file_chunk, file_key, _chunk_start, _chunk_end} ->
        MapSet.member?(file_keys, file_key)
      end)
      |> MapSet.new()

    files =
      snap
      |> db_keys_stream({:file, 0}, {:"file\0", 0})
      |> Stream.filter(fn {:file, file_key} ->
        MapSet.member?(file_keys, file_key)
      end)
      |> MapSet.new()

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

    memo_index =
      snap
      |> db_keys_stream({:memo_index, 0, 0}, {:"memo_index\0", 0, 0})
      |> Stream.filter(fn {:memo_index, reader_hash, _memo_key} ->
        MapSet.member?(hashes, reader_hash)
      end)
      |> MapSet.new()

    memo_keys =
      memo_index
      |> Enum.map(fn {:memo_index, _reader_hash, key} -> key end)
      |> MapSet.new()

    memos =
      snap
      |> db_keys_stream({:memo, 0}, {:"memo\0", 0})
      |> Stream.filter(fn {:memo, key} ->
        MapSet.member?(memo_keys, key)
      end)
      |> MapSet.new()

    room_invite_index =
      snap
      |> db_keys_stream({:room_invite_index, 0, 0}, {:"room_invite_index\0", 0, 0})
      |> Stream.filter(fn {:room_invite_index, reader_hash, _invite_key} ->
        MapSet.member?(hashes, reader_hash)
      end)
      |> MapSet.new()

    room_invite_keys =
      room_invite_index
      |> Enum.map(fn {:room_invite_index, _reader_hash, invite_key} -> invite_key end)
      |> MapSet.new()

    room_invites =
      snap
      |> db_keys_stream({:room_invite, 0}, {:"room_invite\0", 0})
      |> Stream.filter(fn {:room_invite, invite_key} ->
        MapSet.member?(room_invite_keys, invite_key)
      end)
      |> MapSet.new()

    acc_set
    |> union_set(chunk_keys)
    |> union_set(file_chunks)
    |> union_set(file_index)
    |> union_set(files)
    |> union_set(memo_index)
    |> union_set(memos)
    |> union_set(room_invite_index)
    |> union_set(room_invites)
  end

  defp db_keys_stream(snap, min, max) do
    CubDB.Snapshot.select(snap, min_key: min, max_key: max)
    |> Stream.map(&just_keys/1)
  end

  defp union_set(list, set) do
    list
    |> MapSet.new()
    |> MapSet.union(set)
  end

  defp just_keys({k, _v}), do: k

  defp hash_pubkeys(list) do
    binhashes = Enum.map(list, &Utils.binhash/1)
    hashes = Enum.map(binhashes, &Utils.hash/1)

    {MapSet.new(binhashes), MapSet.new(hashes)}
  end
end
