defmodule ChatWeb.ElectricShapesTest do
  @moduledoc """
  Tests the /electric/v1/shapes forward endpoint that allows
  client-controlled where/columns query params.
  """
  use ChatWeb.ConnCase, async: true, group: :electric_http
  use ChatWeb.DataCase

  alias Chat.Data.Schemas.File
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.FileId
  alias Chat.Data.Types.UserHash
  alias Chat.Repo
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    conn = Sandbox.init_test_session(conn, Chat.Repo)
    {:ok, conn: conn}
  end

  describe "GET /electric/v1/shapes - file_chunks with where" do
    test "fetches a specific chunk by file_id and chunk_index", %{conn: conn} do
      {file_id, _uploader_hash} = insert_file_with_chunks!(chunk_count: 2)

      conn = get_shape(conn, "file_chunks", ~s(file_id = '#{file_id}' AND chunk_index = 1))

      assert conn.status == 200

      [row] = data_rows(conn)
      assert row["value"]["chunk_index"] == "1"
      assert row["value"]["file_id"] == file_id
    end

    test "rejects requests for disallowed tables", %{conn: conn} do
      conn = get_shape(conn, "upload_chunks")

      assert conn.status == 400
      assert %{"error" => _} = Jason.decode!(conn.resp_body)
    end

    test "rejects requests without table param", %{conn: conn} do
      conn = get(conn, "/electric/v1/shapes", %{"offset" => "-1"})

      assert conn.status == 400
      assert %{"error" => "missing table parameter"} = Jason.decode!(conn.resp_body)
    end
  end

  defp get_shape(conn, table, where \\ nil) do
    params =
      %{"table" => table, "offset" => "-1"}
      |> then(fn p -> if where, do: Map.put(p, "where", where), else: p end)

    get(conn, "/electric/v1/shapes", params)
  end

  defp data_rows(conn) do
    conn.resp_body
    |> Jason.decode!()
    |> Enum.filter(&match?(%{"headers" => _, "value" => _}, &1))
  end

  defp insert_file_with_chunks!(opts) do
    chunk_count = Keyword.fetch!(opts, :chunk_count)
    file_id = FileId.generate()
    uploader_hash = UserHash.from_binary(:crypto.strong_rand_bytes(64))

    insert_user_card!(uploader_hash)
    insert_file!(file_id, uploader_hash, chunk_count)

    for i <- 0..(chunk_count - 1) do
      insert_chunk!(file_id, i, uploader_hash)
    end

    {file_id, uploader_hash}
  end

  defp insert_user_card!(user_hash) do
    %UserCard{}
    |> UserCard.create_changeset(%{
      user_hash: user_hash,
      sign_pkey: :crypto.strong_rand_bytes(32),
      contact_pkey: :crypto.strong_rand_bytes(32),
      contact_cert: :crypto.strong_rand_bytes(64),
      crypt_pkey: :crypto.strong_rand_bytes(32),
      crypt_cert: :crypto.strong_rand_bytes(64),
      name: "Test Uploader",
      deleted_flag: false,
      owner_timestamp: 0,
      sign_b64: :crypto.strong_rand_bytes(64)
    })
    |> Repo.insert!()
  end

  defp insert_file!(file_id, uploader_hash, chunk_count) do
    %File{}
    |> File.create_changeset(%{
      file_id: file_id,
      uploader_hash: uploader_hash,
      total_size: chunk_count * 4_194_304,
      chunk_size: 4_194_304,
      chunk_count: chunk_count,
      chunk_sign_hashes: for(_ <- 1..chunk_count, do: :crypto.strong_rand_bytes(32)),
      owner_timestamp: 1,
      deleted_flag: false,
      sign_b64: :crypto.strong_rand_bytes(64)
    })
    |> Repo.insert!()
  end

  defp insert_chunk!(file_id, index, uploader_hash) do
    %FileChunk{}
    |> FileChunk.create_changeset(%{
      file_id: file_id,
      chunk_index: index,
      data_hash: "fd_" <> String.duplicate("ab", 64),
      size: 100,
      uploader_hash: uploader_hash,
      owner_timestamp: 1,
      sign_b64: :crypto.strong_rand_bytes(64)
    })
    |> Repo.insert!()
  end
end
