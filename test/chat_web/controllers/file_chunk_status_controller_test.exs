defmodule ChatWeb.FileChunkStatusControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.ChunkStore
  alias Chat.Data.Types.FileId
  alias Chat.Db.Common

  @chunk_status_path "/electric/v1/file_chunk_status"

  setup %{conn: conn} do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("chunk_status_ctrl_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    prev_base = Common.get_chat_db_env(:files_base_dir)
    Common.put_chat_db_env(:files_base_dir, tmp_dir)

    on_exit(fn ->
      Common.put_chat_db_env(:files_base_dir, prev_base)
      File.rm_rf!(tmp_dir)
    end)

    {:ok, conn: conn, tmp_dir: tmp_dir}
  end

  describe "GET /electric/v1/file_chunk_status" do
    test "returns on_disk and missing counts for a file", %{conn: conn, tmp_dir: tmp_dir} do
      file_id = FileId.generate()
      store_chunks(file_id, 2, tmp_dir)
      mark_missing_chunks(file_id, 2)

      statuses = conn |> get(chunk_status_path(file_id)) |> decode_statuses()

      assert statuses[file_id] == %{"on_disk" => 2, "missing" => 2}
    end

    test "returns 0/0 for an unknown file_id", %{conn: conn} do
      file_id = FileId.generate()

      statuses = conn |> get(chunk_status_path(file_id)) |> decode_statuses()

      assert statuses[file_id] == %{"on_disk" => 0, "missing" => 0}
    end

    test "returns 400 when file_ids param is missing", %{conn: conn} do
      conn = get(conn, @chunk_status_path)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "missing file_ids parameter"
    end

    test "dedupes and trims comma-separated file_ids", %{conn: conn, tmp_dir: tmp_dir} do
      file_id = FileId.generate()
      store_chunks(file_id, 1, tmp_dir)

      statuses =
        conn
        |> get(chunk_status_path("#{file_id}, #{file_id} ,#{file_id}"))
        |> decode_statuses()

      assert map_size(statuses) == 1
      assert statuses[file_id]["on_disk"] == 1
    end

    test "returns independent counts for multiple file_ids", %{conn: conn, tmp_dir: tmp_dir} do
      file_id_a = FileId.generate()
      file_id_b = FileId.generate()

      store_chunks(file_id_a, 1, tmp_dir)
      mark_missing_chunks(file_id_b, 3)

      statuses =
        conn
        |> get(chunk_status_path("#{file_id_a},#{file_id_b}"))
        |> decode_statuses()

      assert statuses[file_id_a] == %{"on_disk" => 1, "missing" => 0}
      assert statuses[file_id_b] == %{"on_disk" => 0, "missing" => 3}
    end
  end

  # Helpers

  defp chunk_status_path(file_ids_param) do
    @chunk_status_path <> "?" <> URI.encode_query(%{"file_ids" => file_ids_param})
  end

  defp store_chunks(file_id, count, tmp_dir) do
    for i <- 0..(count - 1), do: ChunkStore.put(file_id, i, "chunk_#{i}", tmp_dir)
  end

  defp mark_missing_chunks(file_id, count) do
    FileData.insert_missing_chunks_placeholders(file_id, count, nil, 1_000_000)
  end

  defp decode_statuses(conn) do
    assert conn.status == 200
    Jason.decode!(conn.resp_body)["statuses"]
  end
end
