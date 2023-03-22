defmodule ChatWeb.UploadChunkControllerTest do
  use ChatWeb.ConnCase
  import Mock

  @chunk_size 10 * 1024 * 1024
  @upload_key "a79f0b663a01b53df466335d23096e61521ca4d1f1d6ef9919281b4e1b4dbdb9"
  @upload_fixture "test/support/fixtures/files/text.txt"

  test "PUT /upload_chunk/{key}", %{conn: conn} do
    with_mock Chat.ChunkedFiles, save_upload_chunk: fn _, _, _ -> :ok end do
      # fill the file
      File.write!(@upload_fixture, :crypto.strong_rand_bytes(3 * @chunk_size))
      file_size = File.stat!(@upload_fixture).size

      responses =
        File.stream!(@upload_fixture, [], @chunk_size)
        |> Stream.with_index()
        |> Stream.map(fn {chunk, index} ->
          offset = index * @chunk_size
          chunk_size = byte_size(chunk)
          {offset, chunk_size, chunk}
        end)
        |> Enum.map(fn {offset, chunk_size, chunk} ->
          %{status: status} =
            conn
            |> put_req_header("content-type", "application/octet-stream")
            |> put_req_header(
              "content-range",
              "bytes #{offset}-#{offset + chunk_size - 1}/#{file_size}"
            )
            |> put_req_header("content-length", "#{chunk_size}")
            |> put("/upload_chunk/#{@upload_key}", chunk)

          status
        end)

      assert [200, 200, 200] = responses

      # empty the file
      File.write(@upload_fixture, "")
    end
  end
end
