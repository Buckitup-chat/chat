defmodule ChatWeb.RouterTest do
  use ChatWeb.ConnCase, async: true

  alias Phoenix.Router

  # {method, path, plug, action} — one row per route not already hit by a request test
  @routes [
    {"GET", "/get/file/proxy/peer/id", ChatWeb.ProxiedFileController, :file},
    {"GET", "/get/image/proxy/peer/id", ChatWeb.ProxiedFileController, :image},
    {"GET", "/privacy-policy.html", ChatWeb.PlainController, :privacy_policy},
    {"GET", "/dev/device_webrtc", ChatWeb.PlainController, :device_webrtc},
    {"PUT", "/upload_chunk/key", ChatWeb.UploadChunkController, :put},
    {"GET", "/proxy-api/select", ChatWeb.ProxyApiController, :select},
    {"GET", "/proxy-api/key-value", ChatWeb.ProxyApiController, :key_value},
    {"GET", "/proxy-api/confirmation-token", ChatWeb.ProxyApiController, :confirmation_token},
    {"POST", "/proxy-api/bulk-get", ChatWeb.ProxyApiController, :bulk_get},
    {"POST", "/proxy-api/register-user", ChatWeb.ProxyApiController, :register_user},
    {"POST", "/proxy-api/create-dialog", ChatWeb.ProxyApiController, :create_dialog},
    {"POST", "/proxy-api/save-parcel", ChatWeb.ProxyApiController, :save_parcel},
    {"POST", "/proxy-api/request-room-access", ChatWeb.ProxyApiController, :request_room_access},
    {"POST", "/proxy-api/approve-room-request", ChatWeb.ProxyApiController,
     :approve_room_request},
    {"POST", "/proxy-api/clean-room-request", ChatWeb.ProxyApiController, :clean_room_request},
    {"POST", "/proxy-api/update", ChatWeb.ProxyApiController, :update},
    {"GET", "/electric/v1/challenge", ChatWeb.ChallengeController, :create},
    {"GET", "/electric/v1/device_identity", ChatWeb.DeviceIdentityController, :show},
    {"OPTIONS", "/electric/v1/read_session", ChatWeb.ReadSessionController, :options},
    {"GET", "/electric/v1/system_identifier", ChatWeb.SystemIdentifierController, :show},
    {"OPTIONS", "/electric/v1/ingest", ChatWeb.ElectricController, :options},
    {"OPTIONS", "/electric/v1/ingest_each", ChatWeb.ElectricController, :options},
    {"GET", "/app/", ChatWeb.FrontendController, :app},
    {"GET", "/app/chats/42", ChatWeb.FrontendController, :app}
  ]

  @electric_sandboxes ~W(
    electric electric/user_cards electric/user_storage electric/user_storage_versions
    electric/files electric/file_chunks electric/dialog_keys electric/dialog_messages
    electric/dialog_message_versions electric/dialog_message_reactions
    electric/dialog_message_receipts electric/user_sandbox electric/dialog_sandbox
    electric/origins electric/origin_sandbox electric/reviews electric/review_public_passwords
    electric/review_post_rights electric/review_revoke_rights electric/review_lists
    electric/vouch_tokens electric/origin_bots electric/origin_settings
    electric/review_write_tokens electric/review_sandbox electric/moderation_sandbox
    electric/origin_reviews electric/contacts_reader electric/admin_sandbox
    electric/vouch_sandbox
  )

  describe "route table" do
    test "routes resolve to their controller action" do
      for {method, path, plug, action} <- @routes do
        assert %{plug: ^plug, plug_opts: ^action} = route(method, path), "#{method} #{path}"
      end
    end

    test "every Electric sandbox page is a LiveView" do
      for path <- @electric_sandboxes do
        assert %{plug: Phoenix.LiveView.Plug, phoenix_live_view: {view, :index, _, _}} =
                 route("GET", "/" <> path),
               path

        assert view |> Module.split() |> Enum.take(2) == ["ChatWeb", "ElectricLive"]
      end
    end

    test "the proxy page is a LiveView" do
      assert %{phoenix_live_view: {ChatWeb.ProxyLive.Index, :proxy, _, _}} =
               route("GET", "/trusted/proxy/peer/")
    end

    test "Absinthe is forwarded under /naive_api" do
      assert %{plug: Absinthe.Plug} = route("POST", "/naive_api")
    end
  end

  describe "pipelines" do
    test ":browser renders HTML with secure headers", %{conn: conn} do
      conn = get(conn, "/")

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert conn.private.phoenix_format == "html"
    end

    test ":api answers JSON with open CORS", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://elsewhere.example")
        |> post("/naive_api", %{"query" => "{ __typename }"})

      assert %{"data" => %{"__typename" => "RootQueryType"}} = json_response(conn, 200)
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end

    test ":electric exposes the sync protocol headers cross-origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://elsewhere.example")
        |> get("/electric/v1/status")

      assert [exposed] = get_resp_header(conn, "access-control-expose-headers")
      assert exposed =~ "electric-handle"
      assert exposed =~ "electric-offset"
    end

    test ":chunk_upload allows chunk headers and exposes retry-after", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://elsewhere.example")
        |> put_req_header("access-control-request-method", "PUT")
        |> options("/electric/v1/file_chunk/file-id/0")

      assert [allowed] = get_resp_header(conn, "access-control-allow-headers")
      assert allowed =~ "x-signature"
    end

    test ":upload answers chunk upload preflight", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://elsewhere.example")
        |> put_req_header("access-control-request-method", "PUT")
        |> options("/upload_chunk/some-key")

      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end
  end

  # Helpers

  defp route(method, path), do: Router.route_info(ChatWeb.Router, method, path, "localhost")
end
