defmodule ChatWeb.ProxiedFileControllerTest do
  use ChatWeb.ConnCase, async: true
  import Rewire

  alias ChatWeb.ProxiedFileController

  @chunk_size Application.compile_env(:chat, :file_chunk_size)
  @hundred_chunks 100 * @chunk_size
  @content "0123456789abcdefghij"
  @size byte_size(@content)
  @server "peer.local"

  defmodule FakeProxy do
    @moduledoc false
    def get_file_info(server, key), do: fetch({:file, server, key})
    def get_file_secrets(server, key), do: fetch({:file_secrets, server, key})
    def read_file_chunk(server, key, start), do: fetch({:file_chunk, server, key, start})

    defp fetch(key), do: Process.get(key) || raise("not on peer")
  end

  rewire(ProxiedFileController, Proxy: FakeProxy, as: Controller)

  setup do
    [remote: remote_file("text/plain", "note.txt")]
  end

  describe "file/2" do
    test "streams the whole remote file as an attachment", %{conn: conn, remote: remote} do
      conn = Controller.file(conn, params(remote))

      assert @content == response(conn, 200)
      assert ["attachment; filename=\"note.txt\""] == get_resp_header(conn, "content-disposition")
      assert ["#{@size}"] == get_resp_header(conn, "content-length")
      assert ["bytes"] == get_resp_header(conn, "accept-ranges")
      assert ["text/plain" <> _] = get_resp_header(conn, "content-type")
    end

    test "serves a closed byte range as partial content", %{conn: conn, remote: remote} do
      conn = conn |> put_req_header("range", "bytes=2-5") |> Controller.file(params(remote))

      assert "2345" == response(conn, 206)
      assert ["bytes 2-5/#{@size}"] == get_resp_header(conn, "content-range")
      assert ["4"] == get_resp_header(conn, "content-length")
    end

    test "serves open-ended ranges up to the end of the file", %{conn: conn, remote: remote} do
      for range <- ["bytes=15-", "bytes=15-*"] do
        conn = conn |> put_req_header("range", range) |> Controller.file(params(remote))

        assert "fghij" == response(conn, 206)
        assert ["bytes 15-19/#{@size}"] == get_resp_header(conn, "content-range")
      end
    end

    test "treats empty or unknown ranges as the whole file", %{conn: conn, remote: remote} do
      for range <- ["bytes=", "bytes=-", "items=0-3"] do
        conn = conn |> put_req_header("range", range) |> Controller.file(params(remote))

        assert @content == response(conn, 206)
        assert ["bytes 0-19/#{@size}"] == get_resp_header(conn, "content-range")
      end
    end

    test "reads secrets of chunks past the first hundred from the peer", %{conn: conn} do
      remote = remote_file("text/plain", "big.bin", @hundred_chunks + @size)
      {key, initial_secret} = remote
      extra_secret = Enigma.generate_secret()

      Process.put({:file_secrets, @server, key}, Enigma.cipher(extra_secret, initial_secret))

      Process.put(
        {:file_chunk, @server, key, @hundred_chunks},
        {Enigma.cipher(@content, extra_secret), @hundred_chunks + @size - 1}
      )

      first = @hundred_chunks + 10
      last = @hundred_chunks + 13

      conn =
        conn
        |> put_req_header("range", "bytes=#{first}-#{last}")
        |> Controller.file(params(remote))

      assert "abcd" == response(conn, 206)
    end
  end

  describe "image/2" do
    test "serves inline with the file content type", %{conn: conn} do
      remote = remote_file("image/png", "pic.png")
      conn = Controller.image(conn, params(remote))

      assert @content == response(conn, 200)
      assert [] == get_resp_header(conn, "content-disposition")
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
    end

    test "forces a binary download with download param", %{conn: conn} do
      remote = remote_file("image/png", "pic.png")
      conn = Controller.image(conn, Map.put(params(remote), "download", "1"))

      assert @content == response(conn, 200)
      assert ["attachment; filename=\"pic.png\""] == get_resp_header(conn, "content-disposition")
      assert ["octet/stream" <> _] = get_resp_header(conn, "content-type")
    end
  end

  describe "denials" do
    test "file unknown to the peer", %{conn: conn, remote: {_key, secret}} do
      unknown = {Enigma.hash(UUID.uuid4()), secret}

      assert "" == conn |> Controller.file(params(unknown)) |> response(404)
    end

    test "wrong secret", %{conn: conn, remote: {key, _secret}} do
      wrong = params({key, Enigma.generate_secret()})

      assert "" == conn |> Controller.file(wrong) |> response(404)
    end

    test "missing secret or server", %{conn: conn, remote: remote} do
      assert "" == conn |> Controller.file(Map.delete(params(remote), "a")) |> response(404)
      assert "" == conn |> Controller.image(Map.delete(params(remote), "server")) |> response(404)
    end

    test "malformed id and secret", %{conn: conn} do
      assert "" ==
               conn
               |> Controller.file(%{"id" => "not-hex", "a" => "x", "server" => @server})
               |> response(404)

      assert "" ==
               conn
               |> Controller.file(%{"id" => "00ff", "a" => "***", "server" => @server})
               |> response(404)
    end

    test "type without a slash", %{conn: conn} do
      odd = remote_file("plaintext", "odd.txt")

      assert "" == conn |> Controller.file(params(odd)) |> response(404)
    end

    test "reversed range", %{conn: conn, remote: remote} do
      conn = conn |> put_req_header("range", "bytes=5-2") |> Controller.file(params(remote))

      assert "" == response(conn, 404)
    end

    test "chunk missing on the peer", %{conn: conn, remote: {key, _} = remote} do
      Process.delete({:file_chunk, @server, key, 0})
      conn = conn |> put_req_header("range", "bytes=0-3") |> Controller.file(params(remote))

      assert "" == response(conn, 404)
    end
  end

  # Helpers

  defp remote_file(type, name, size \\ @size) do
    key = Enigma.hash(UUID.uuid4())
    secret = Enigma.generate_secret()
    info = [key, Base.encode64(secret), "#{size}", type, name, "time"]

    Process.put({:file, @server, key}, Enigma.cipher(info, secret))
    Process.put({:file_chunk, @server, key, 0}, {Enigma.cipher(@content, secret), @size - 1})

    {key, secret}
  end

  defp params({key, secret}) do
    %{
      "id" => Base.encode16(key, case: :lower),
      "a" => Base.url_encode64(secret),
      "server" => @server
    }
  end
end
