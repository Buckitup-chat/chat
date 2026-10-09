defmodule Chat.NetworkSynchronization.Electric.GatedFetchTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Chat.NetworkSynchronization.Electric.GatedFetch
  alias Chat.NetworkSynchronization.Electric.ReadSessions
  alias Electric.Client.Fetch

  @peer "http://peer.local"

  setup do
    name = :"gated_fetch_rs_#{System.unique_integer([:positive])}"
    start_supervised!({ReadSessions, name: name, opener: fn _, _ -> {:ok, "tok", 300} end})
    %{rs: name}
  end

  test "validate_opts requires peer_url and shape" do
    assert {:error, _} = GatedFetch.validate_opts(shape: :file)
    assert {:ok, opts} = GatedFetch.validate_opts(peer_url: @peer, shape: :file)
    assert opts[:peer_url] == @peer
  end

  test "opens a session on 401 and retries the request with the bearer", %{rs: rs} do
    opts = gated_opts(rs, peer_plug_requiring_bearer("tok", self()))

    assert {:ok, %Fetch.Response{status: 200, shape_handle: "h1"}} =
             GatedFetch.fetch(shape_request(), opts)

    assert_received {:auth, []}
    assert_received {:auth, ["Bearer tok"]}
  end

  defp gated_opts(read_sessions, plug) do
    {:ok, opts} =
      GatedFetch.validate_opts(
        peer_url: @peer,
        shape: :user_card,
        read_sessions: read_sessions,
        request: [plug: plug]
      )

    opts
  end

  defp shape_request do
    %Fetch.Request{endpoint: URI.parse("#{@peer}/electric/v1/shapes"), authenticated: true}
  end

  defp peer_plug_requiring_bearer(token, test_pid) do
    expected = ["Bearer #{token}"]

    fn conn ->
      auth = get_req_header(conn, "authorization")
      send(test_pid, {:auth, auth})

      case auth do
        ^expected -> empty_shape_response(conn)
        _ -> read_session_required_response(conn)
      end
    end
  end

  defp empty_shape_response(conn) do
    conn
    |> put_resp_header("electric-handle", "h1")
    |> put_resp_header("electric-offset", "0_0")
    |> put_resp_content_type("application/json")
    |> send_resp(200, "[]")
  end

  defp read_session_required_response(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"read_session_required","shape":"user_card"}))
  end
end
