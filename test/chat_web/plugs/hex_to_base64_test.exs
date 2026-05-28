defmodule ChatWeb.Plugs.HexToBase64Test do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ChatWeb.Plugs.HexToBase64Adapter, as: HexToBase64

  defp call_plug(body, content_type \\ "application/json") do
    :get
    |> conn("/")
    |> put_resp_content_type(content_type)
    |> HexToBase64.call(HexToBase64.init([]))
    |> send_resp(200, Jason.encode!(body))
  end

  defp decoded_body(conn), do: Jason.decode!(conn.resp_body)

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
end
