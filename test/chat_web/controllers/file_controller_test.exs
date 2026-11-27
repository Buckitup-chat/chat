defmodule ChatWeb.FileControllerTest do
  use ChatWeb.ConnCase, async: true, group: :cubdb

  alias Chat.Broker
  alias Chat.ChunkedFiles
  alias Chat.Content.Files
  alias Chat.Db.ChangeTracker

  @content "0123456789abcdefghij"
  @size byte_size(@content)

  setup do
    [stored: stored_file("text/plain", "note.txt")]
  end

  describe "GET /get/file/:id" do
    test "streams the whole file as an attachment", %{conn: conn, stored: file} do
      conn = get(conn, file_path(file))

      assert @content == response(conn, 200)
      assert ["attachment; filename=\"note.txt\""] == get_resp_header(conn, "content-disposition")
      assert ["#{@size}"] == get_resp_header(conn, "content-length")
      assert ["bytes"] == get_resp_header(conn, "accept-ranges")
      assert ["text/plain" <> _] = get_resp_header(conn, "content-type")
    end

    test "serves a closed byte range as partial content", %{conn: conn, stored: file} do
      conn = conn |> put_req_header("range", "bytes=2-5") |> get(file_path(file))

      assert "2345" == response(conn, 206)
      assert ["bytes 2-5/#{@size}"] == get_resp_header(conn, "content-range")
      assert ["4"] == get_resp_header(conn, "content-length")
    end

    test "serves open-ended ranges up to the end of the file", %{conn: conn, stored: file} do
      for range <- ["bytes=15-", "bytes=15-*"] do
        conn = conn |> put_req_header("range", range) |> get(file_path(file))

        assert "fghij" == response(conn, 206)
        assert ["bytes 15-19/#{@size}"] == get_resp_header(conn, "content-range")
      end
    end

    test "treats empty or unknown ranges as the whole file", %{conn: conn, stored: file} do
      for range <- ["bytes=", "bytes=-", "items=0-3"] do
        conn = conn |> put_req_header("range", range) |> get(file_path(file))

        assert @content == response(conn, 206)
        assert ["bytes 0-19/#{@size}"] == get_resp_header(conn, "content-range")
      end
    end

    test "answers 404 on a reversed range", %{conn: conn, stored: file} do
      conn = conn |> put_req_header("range", "bytes=5-2") |> get(file_path(file))

      assert "" == response(conn, 404)
    end
  end

  describe "GET /get/image/:id" do
    test "serves inline with the file content type", %{conn: conn} do
      image = stored_file("image/png", "pic.png")
      conn = get(conn, image_path(image))

      assert @content == response(conn, 200)
      assert [] == get_resp_header(conn, "content-disposition")
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
    end

    test "forces a binary download with ?download", %{conn: conn} do
      image = stored_file("image/png", "pic.png")
      conn = get(conn, image_path(image) <> "&download=1")

      assert @content == response(conn, 200)
      assert ["attachment; filename=\"pic.png\""] == get_resp_header(conn, "content-disposition")
      assert ["octet/stream" <> _] = get_resp_header(conn, "content-type")
    end
  end

  describe "denials" do
    test "unknown file id", %{conn: conn, stored: {_key, secret}} do
      unknown = {Enigma.hash(UUID.uuid4()), secret}

      assert "" == conn |> get(file_path(unknown)) |> response(404)
    end

    test "wrong secret", %{conn: conn, stored: {key, _secret}} do
      assert "" == conn |> get(file_path({key, Enigma.generate_secret()})) |> response(404)
    end

    test "missing secret", %{conn: conn, stored: {key, _secret}} do
      assert "" == conn |> get(~p"/get/file/#{Base.encode16(key, case: :lower)}") |> response(404)
    end

    test "malformed id and secret", %{conn: conn} do
      assert "" == conn |> get("/get/file/not-hex?a=x") |> response(404)
      assert "" == conn |> get("/get/image/00ff?a=***") |> response(404)
    end

    test "type without a slash", %{conn: conn} do
      odd = stored_file("plaintext", "odd.txt")

      assert "" == conn |> get(file_path(odd)) |> response(404)
    end
  end

  describe "GET /get/backup/:key" do
    test "hands out a brokered backup exactly once", %{conn: conn} do
      key = Broker.store({"backup.data", "backup bytes"})

      first = get(conn, ~p"/get/backup/#{key}")

      assert "backup bytes" == response(first, 200)

      assert ["attachment; filename=\"backup.data\""] ==
               get_resp_header(first, "content-disposition")

      assert ["application/octet-stream" <> _] = get_resp_header(first, "content-type")

      assert "" == conn |> get(~p"/get/backup/#{key}") |> response(404)
    end

    test "answers 404 on an unknown key", %{conn: conn} do
      assert "" == conn |> get(~p"/get/backup/#{UUID.uuid4()}") |> response(404)
    end
  end

  # Helpers

  defp stored_file(type, name) do
    chunk_key = Enigma.hash(UUID.uuid4())
    chunk_secret = ChunkedFiles.new_upload(chunk_key)
    :ok = ChunkedFiles.save_upload_chunk(chunk_key, {0, @size - 1}, @size, @content)

    [chunk_key, Base.encode64(chunk_secret), "#{@size}", type, name, "time"]
    |> Files.add()
    |> tap(fn _ -> ChangeTracker.await() end)
  end

  defp file_path({key, secret}),
    do: ~p"/get/file/#{Base.encode16(key, case: :lower)}?a=#{Base.url_encode64(secret)}"

  defp image_path({key, secret}),
    do: ~p"/get/image/#{Base.encode16(key, case: :lower)}?a=#{Base.url_encode64(secret)}"
end
