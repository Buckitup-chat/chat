defmodule Chat.Db.Scope.InvitationLevel do
  @moduledoc """
  Process cargo room invitations
  """
  import Chat.Db.Scope.Utils

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
end
