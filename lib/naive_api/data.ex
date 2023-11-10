defmodule NaiveApi.Data do
  @moduledoc "Data transferring functions for API"
  use NaiveApi, :resolver

  def all_keys(_, _) do
    Chat.Db.db()
    |> Chat.Db.Scope.Full.keys()
    |> MapSet.to_list()
    |> Enum.map(&serialize_key/1)
    |> Enum.reject(&is_nil/1)
    |> ok()
  end

  def get_value(%{key: key}, _) do
    key
    |> deserialize_key()
    |> Chat.db_get()
    |> :erlang.term_to_binary([:compressed])
    |> bits_encode()
    |> ok()
  end

  def deserialize_value(string) do
    string
    |> bits_decode()
    |> :erlang.binary_to_term([:safe])
  rescue
    _ -> nil
  end

  def serialize_key(key) when is_tuple(key) do
    key
    |> Tuple.to_list()
    |> Enum.map_join("/", fn
      a when is_atom(a) -> a |> to_string()
      n when is_integer(n) -> n |> to_string()
      <<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> = uuid -> uuid
      b when is_bitstring(b) -> b |> bits_encode()
      t when is_tuple(t) -> t |> serialize_key()
    end)
  end

  def serialize_key(_), do: nil

  def deserialize_key(string) do
    string
    |> String.split("/")
    |> case do
      ["users", key] ->
        {:users, key |> bits_decode()}

      ["dialogs", key] ->
        {:dialogs, key |> bits_decode()}

      ["rooms", key] ->
        {:rooms, key |> bits_decode()}

      ["memo", uuid] ->
        {:memo, uuid}

      ["memo_index", key, uuid] ->
        {:memo_index, key |> bits_decode(), uuid}

      ["file", key] ->
        {:file, key |> bits_decode()}

      ["file_index", reader, key, uuid] ->
        {:file_index, reader |> bits_decode(), key |> bits_decode(), uuid}

      # coveralls-ignore-next-line
      ["upload_index", key] ->
        {:upload_index, key |> bits_decode()}

      # coveralls-ignore-next-line
      ["file_secrets", key] ->
        {:file_secrets, key |> bits_decode()}

      ["room_invite", uuid] ->
        {:room_invite, uuid}

      ["room_invite_index", key, uuid] ->
        {:room_invite_index, key |> bits_decode(), uuid}

      ["room_message", key, index, msg_id] ->
        {:room_message, key |> bits_decode(), index |> to_int(), msg_id |> bits_decode()}

      ["dialog_message", key, index, msg_id] ->
        {:dialog_message, key |> bits_decode(), index |> to_int(), msg_id |> bits_decode()}

      ["file_chunk", id, first, last] ->
        {:file_chunk, id |> bits_decode(), first |> to_int(), last |> to_int()}

      ["chunk_key", "file_chunk", id, first, last] ->
        {:chunk_key, {:file_chunk, id |> bits_decode(), first |> to_int(), last |> to_int()}}

      ["action_log", index, key] ->
        {:action_log, index |> to_int(), key |> bits_decode()}

      _ ->
        nil
    end
  rescue
    _e ->
      nil
  end

  defp bits_encode(x), do: Base.url_encode64(x)
  defp bits_decode(x), do: Base.url_decode64!(x)

  defp to_int(str), do: String.to_integer(str)
end
