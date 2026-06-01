defmodule ChatWeb.Plugs.ElectricIngestThrottleTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Chat.Upload.IngestThrottle
  alias ChatWeb.Plugs.ElectricIngestThrottle

  test "passes through non-heavy mutations without taking a token" do
    throttle = start_throttle(1)

    conn = call_plug(%{"mutations" => [files_mutation()]}, throttle)

    refute conn.halted
    assert IngestThrottle.in_use(throttle) == 0
  end

  test "passes through and holds a token for file_chunk mutations" do
    throttle = start_throttle(1)

    conn = call_plug(%{"mutations" => [file_chunk_mutation()]}, throttle)

    refute conn.halted
    assert IngestThrottle.in_use(throttle) == 1
  end

  test "releases the token after the response is sent (before_send)" do
    throttle = start_throttle(1)

    call_plug(%{"mutations" => [file_chunk_mutation()]}, throttle)
    |> send_resp(200, "ok")

    # before_send fired during send_resp; the cast then settles.
    _ = IngestThrottle.in_use(throttle)
    assert IngestThrottle.in_use(throttle) == 0
  end

  test "rejects with 429 + Retry-After when the throttle is full" do
    throttle = start_throttle(1)

    # Exhaust the single token from a separate, long-lived process.
    test = self()

    spawn(fn ->
      :ok = IngestThrottle.checkout(throttle)
      send(test, :held)
      Process.sleep(:infinity)
    end)

    assert_receive :held

    conn = call_plug(%{"mutations" => [file_chunk_mutation()]}, throttle)

    assert conn.halted
    assert conn.status == 429
    assert get_resp_header(conn, "retry-after") == ["3"]
    assert %{"error" => "upload_busy", "retry_after" => 3} = Jason.decode!(conn.resp_body)
  end

  test "tolerates schema-qualified relation lists" do
    throttle = start_throttle(1)

    mutation = %{"syncMetadata" => %{"relation" => ["public", "file_chunks"]}}
    conn = call_plug(%{"mutations" => [mutation]}, throttle)

    refute conn.halted
    assert IngestThrottle.in_use(throttle) == 1
  end

  defp start_throttle(limit) do
    name = :"throttle_#{System.unique_integer([:positive])}"
    start_supervised!({IngestThrottle, name: name, limit: limit, retry_after_seconds: 3})
    name
  end

  defp call_plug(params, throttle) do
    :post
    |> conn("/electric/v1/ingest", "")
    |> Map.put(:params, params)
    |> ElectricIngestThrottle.call(ElectricIngestThrottle.init(throttle: throttle))
  end

  defp file_chunk_mutation,
    do: %{"type" => "insert", "syncMetadata" => %{"relation" => "file_chunks"}}

  defp files_mutation,
    do: %{"type" => "insert", "syncMetadata" => %{"relation" => "files"}}
end
