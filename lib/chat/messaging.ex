defmodule Chat.Messaging do
  @moduledoc """
  Common processing to porcess message feed (in rooms and dialogs)


  Message lifecycle:
  - creation
  - encryption
  - storing
  - retrieval
  - decryption
  - contnent enrichment 

  """

  alias Chat.DbKeys, as: DbKeys
  alias Chat.Utils.StorageId, as: StorageId

  def preload_content(messages, data_getter_fn \\ &get_from_current_db/1) do
    messages_and_db_keys =
      messages
      |> Enum.map(fn msg ->
        keys = message_to_content_key_list(msg)
        {msg, keys}
      end)

    data =
      messages_and_db_keys
      |> Enum.flat_map(&elem(&1, 1))
      |> then(data_getter_fn)

    messages_and_db_keys
    |> Enum.map(fn {msg, keys} ->
      message_and_content_data_to_enriched_msg(msg, data |> Map.take(keys))
    end)
  end

  defp message_to_content_key_list(msg) do
    case msg.type do
      file_type when file_type in [:image, :audio, :file, :video] ->
        [msg.content |> StorageId.from_json_to_key() |> DbKeys.file()]

      :text ->
        []

      :memo ->
        [msg.content |> StorageId.from_json_to_key() |> DbKeys.memo()]

      _todo ->
        []
    end
  end

  defp message_and_content_data_to_enriched_msg(msg, data_map) do
    case msg.type do
      file_type when file_type in [:image, :audio, :file, :video] ->
        {key, secret} = msg.content |> StorageId.from_json()
        db_key = DbKeys.file(key)

        file_info =
          data_map[db_key]
          |> Enum.map(&Enigma.decipher(&1, secret))

        msg
        |> Map.from_struct()
        |> Map.put(:file_info, file_info)
        |> Map.put(:file_url, ChatWeb.Utils.get_file_url(:file, key, secret))

      :memo ->
        {key, secret} = msg.content |> StorageId.from_json()
        db_key = DbKeys.memo(key)

        data =
          if data_map[db_key],
            do: data_map[db_key] |> Enigma.decipher(secret),
            else: ""

        msg
        |> Map.from_struct()
        |> Map.put(:memo, data)

      :text ->
        msg

      _todo ->
        msg
    end
  end

  defp get_from_current_db(keys_list) do
    keys_list
    |> Enum.sort()
    |> Map.new(fn key ->
      {key, Chat.Db.get(key)}
    end)
  end
end
