defmodule ChatWeb.FileChunkStatusController do
  use ChatWeb, :controller

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore

  def index(conn, params) do
    case params do
      %{"file_ids" => file_ids_str} ->
        statuses = file_ids_str |> parse_file_ids() |> build_statuses()
        json(conn, %{statuses: statuses})

      _ ->
        send_resp(conn, 400, Jason.encode!(%{error: "missing file_ids parameter"}))
    end
  end

  defp parse_file_ids(file_ids_str) do
    file_ids_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp build_statuses(file_ids) do
    missing_counts = FileData.missing_chunk_counts(file_ids)

    Map.new(file_ids, fn file_id ->
      {file_id,
       %{
         on_disk: ChunkStore.count_on_disk(file_id),
         missing: Map.get(missing_counts, file_id, 0)
       }}
    end)
  end
end
