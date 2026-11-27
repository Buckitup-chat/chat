defmodule ChatWeb.Plugs.HexToBase64Test do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ChatWeb.Plugs.HexToBase64Adapter, as: HexToBase64

  defmodule FakeAdapter do
    @moduledoc false

    def chunk(:closed, _data), do: {:error, :closed}
    def chunk(:inner, data), do: {:ok, data, :chunked}
    def send_chunked(:inner, _status, _headers), do: {:ok, nil, :chunked}
    def send_resp(:inner, _status, _headers, body), do: {:ok, body, :sent}
    def send_file(:inner, _status, _headers, _path, _offset, _length), do: {:ok, nil, :file}
    def get_peer_data(payload), do: {:peer, payload}
    def get_http_protocol(payload), do: {:protocol, payload}
    def inform(payload, status, _headers), do: {:inform, payload, status}
    def push(payload, path, _headers), do: {:push, payload, path}
    def read_req_body(:inner, _opts), do: {:ok, "body", :read}
    def read_req_body(:more, _opts), do: {:more, "part", :read}
    def read_req_body(:error, _opts), do: {:error, :timeout}
    def upgrade(payload, protocol, _opts), do: {:upgrade, payload, protocol}
  end

  defp call_plug(body, content_type \\ "application/json") do
    :get
    |> conn("/")
    |> put_resp_content_type(content_type)
    |> HexToBase64.call(HexToBase64.init([]))
    |> send_resp(200, Jason.encode!(body))
  end

  defp decoded_body(conn), do: Jason.decode!(conn.resp_body)

  defp json_headers, do: [{"content-type", "application/json; charset=utf-8"}]

  describe "scalar bytea" do
    test "converts hex-encoded bytea to base64" do
      bin = :crypto.strong_rand_bytes(32)
      hex_value = "\\x" <> Base.encode16(bin)

      conn = call_plug([%{"value" => %{"sign_pkey" => hex_value}}])

      [%{"value" => %{"sign_pkey" => result}}] = decoded_body(conn)
      assert result == Base.encode64(bin, padding: false)
    end

    test "leaves non-hex strings unchanged" do
      conn = call_plug([%{"value" => %{"name" => "Alice"}}])

      [%{"value" => %{"name" => "Alice"}}] = decoded_body(conn)
    end

    test "leaves invalid hex unchanged" do
      conn = call_plug([%{"value" => %{"bad" => "\\xZZZZ"}}])

      [%{"value" => %{"bad" => "\\xZZZZ"}}] = decoded_body(conn)
    end

    test "leaves odd-length hex unchanged" do
      conn = call_plug([%{"value" => %{"bad" => "\\xABC"}}])

      [%{"value" => %{"bad" => "\\xABC"}}] = decoded_body(conn)
    end
  end

  describe "bytea array" do
    test "converts Postgres hex array literal to JSON array of base64" do
      bin1 = :crypto.strong_rand_bytes(16)
      bin2 = :crypto.strong_rand_bytes(16)

      pg_array =
        ~s({"\\\\x#{Base.encode16(bin1)}","\\\\x#{Base.encode16(bin2)}"})

      conn = call_plug([%{"value" => %{"chunk_sign_hashes" => pg_array}}])

      [%{"value" => %{"chunk_sign_hashes" => result}}] = decoded_body(conn)

      assert result == [
               Base.encode64(bin1, padding: false),
               Base.encode64(bin2, padding: false)
             ]
    end

    test "leaves non-hex arrays unchanged" do
      conn = call_plug([%{"value" => %{"tags" => "{foo,bar}"}}])

      [%{"value" => %{"tags" => "{foo,bar}"}}] = decoded_body(conn)
    end
  end

  describe "early skip" do
    test "skips JSON without hex values, body unchanged" do
      body = Jason.encode!([%{"value" => %{"name" => "Alice", "count" => "42"}}])

      conn =
        :get
        |> conn("/")
        |> put_resp_content_type("application/json")
        |> HexToBase64.call(HexToBase64.init([]))
        |> send_resp(200, body)

      assert conn.resp_body == body
    end

    test "converts JSON with hex values, body changed" do
      body = Jason.encode!([%{"value" => %{"sign_pkey" => "\\xABCD"}}])

      conn =
        :get
        |> conn("/")
        |> put_resp_content_type("application/json")
        |> HexToBase64.call(HexToBase64.init([]))
        |> send_resp(200, body)

      refute conn.resp_body == body
      [%{"value" => %{"sign_pkey" => result}}] = decoded_body(conn)
      assert result == Base.encode64(<<0xAB, 0xCD>>, padding: false)
    end
  end

  describe "passthrough" do
    test "skips non-json responses" do
      conn =
        :get
        |> conn("/")
        |> put_resp_content_type("text/event-stream")
        |> HexToBase64.call(HexToBase64.init([]))
        |> send_resp(200, "data: hello\n\n")

      assert conn.resp_body == "data: hello\n\n"
    end

    test "skips chunked responses with nil body" do
      conn =
        :get
        |> conn("/")
        |> put_resp_content_type("application/json")
        |> HexToBase64.call(HexToBase64.init([]))
        |> send_chunked(200)

      assert conn.state == :chunked
    end

    test "skips error responses" do
      conn =
        :get
        |> conn("/")
        |> put_resp_content_type("application/json")
        |> HexToBase64.call(HexToBase64.init([]))
        |> send_resp(400, Jason.encode!(%{"error" => "bad"}))

      assert decoded_body(conn) == %{"error" => "bad"}
    end
  end

  describe "bytea array edge cases" do
    test "converts arrays with NULL elements" do
      conn = call_plug([%{"v" => ~s({"\\\\xABCD",NULL})}])

      assert [%{"v" => [abcd, nil]}] = decoded_body(conn)
      assert abcd == Base.encode64(<<0xAB, 0xCD>>, padding: false)
    end

    test "leaves arrays unchanged unless every element is valid hex" do
      for array <- [
            ~s({"\\\\xABCD","plain"}),
            ~s({"\\\\xA"}),
            ~s({{"\\\\xABCD"}}),
            ~S({}),
            ~S({"unterminated)
          ] do
        assert [%{"v" => ^array}] = decoded_body(call_plug([%{"v" => array}]))
      end
    end
  end

  describe "send_resp edge cases" do
    test "passes nil and iodata bodies through" do
      assert {:ok, nil, {FakeAdapter, :sent}} =
               HexToBase64.send_resp({FakeAdapter, :inner}, 200, json_headers(), nil)

      body = ["{\"a\":", "\"\\\\xAB\"}"]

      assert {:ok, ^body, {FakeAdapter, :sent}} =
               HexToBase64.send_resp({FakeAdapter, :inner}, 200, json_headers(), body)
    end

    test "passes a body that looks like hex but is not JSON through" do
      body = "not json \\xAB"

      assert {:ok, ^body, _} =
               HexToBase64.send_resp({FakeAdapter, :inner}, 200, json_headers(), body)
    end
  end

  describe "chunk/2" do
    test "converts hex values in JSON chunks" do
      chunk = Jason.encode!([%{"k" => "\\xABCD"}])

      assert {:ok, sent, {FakeAdapter, :chunked}} =
               HexToBase64.chunk({FakeAdapter, :inner}, chunk)

      assert [%{"k" => "q80"}] = Jason.decode!(sent)
    end

    test "passes chunks it cannot or need not convert through" do
      for chunk <- ["plain text", ["not json ", "\\\\x"], :not_iodata] do
        assert {:ok, ^chunk, _} = HexToBase64.chunk({FakeAdapter, :inner}, chunk)
      end
    end

    test "returns inner adapter errors unchanged" do
      assert {:error, :closed} = HexToBase64.chunk({FakeAdapter, :closed}, "data")
    end
  end

  describe "adapter delegation" do
    test "wraps the payload returned by the inner adapter" do
      adapter = {FakeAdapter, :inner}

      assert {:ok, nil, {FakeAdapter, :chunked}} = HexToBase64.send_chunked(adapter, 200, [])
      assert {:ok, nil, {FakeAdapter, :file}} = HexToBase64.send_file(adapter, 200, [], "p", 0, 1)
      assert {:ok, "body", {FakeAdapter, :read}} = HexToBase64.read_req_body(adapter, [])

      assert {:more, "part", {FakeAdapter, :read}} =
               HexToBase64.read_req_body({FakeAdapter, :more}, [])

      assert {:error, :timeout} = HexToBase64.read_req_body({FakeAdapter, :error}, [])
    end

    test "passes the rest straight to the inner adapter" do
      adapter = {FakeAdapter, :inner}

      assert {:peer, :inner} = HexToBase64.get_peer_data(adapter)
      assert {:protocol, :inner} = HexToBase64.get_http_protocol(adapter)
      assert {:inform, :inner, 103} = HexToBase64.inform(adapter, 103, [])
      assert {:push, :inner, "/a.js"} = HexToBase64.push(adapter, "/a.js", [])
      assert {:upgrade, :inner, :websocket} = HexToBase64.upgrade(adapter, :websocket, [])
    end

    test "unwrap/1 restores the inner adapter and ignores unwrapped conns" do
      conn = conn(:get, "/")
      wrapped = HexToBase64.wrap(conn)

      assert {HexToBase64, _} = wrapped.adapter
      assert HexToBase64.unwrap(wrapped).adapter == conn.adapter
      assert HexToBase64.unwrap(conn) == conn
    end
  end
end
