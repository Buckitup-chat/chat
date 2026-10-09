defmodule ChatWeb.Plugs.ElectricReadGateTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ReadGateHelpers

  alias Chat.Data.Types.FileId
  alias Phoenix.Sync.Sandbox

  setup %{conn: conn} do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")

    %{conn: Sandbox.init_test_session(conn, Chat.Repo), owner: owner, owner_card: owner_card}
  end

  describe "not enforced" do
    test "open mode reads without a token", %{conn: conn, owner_card: owner_card} do
      put_gate(:open, owner_card)

      assert get_shape(conn, "user_cards").status == 200
    end

    test "guarded mode reads without a token", %{conn: conn, owner_card: owner_card} do
      put_gate(:guarded, owner_card)

      assert get_shape(conn, "user_cards").status == 200
    end

    test "trust mode without an owner reads without a token", %{conn: conn} do
      put_gate(:trust)

      assert get_shape(conn, "user_cards").status == 200
    end
  end

  describe "trust mode with an owner" do
    setup %{owner_card: owner_card} do
      put_gate(:trust, owner_card)
    end

    test "no token is rejected with the table's shape", %{conn: conn} do
      conn = get_shape(conn, "user_cards")

      assert %{"error" => "read_session_required", "shape" => "user_card"} =
               json_response(conn, 401)
    end

    test "unknown token is rejected", %{conn: conn} do
      conn = conn |> with_bearer("bogus") |> get_shape("user_cards")

      assert json_response(conn, 401)
    end

    test "session token passes and response is private", ctx do
      conn = ctx.conn |> with_bearer(owner_session(ctx, "user_card")) |> get_shape("user_cards")

      assert conn.status == 200
      assert [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control =~ "private"
      refute cache_control =~ "public"
      assert [vary] = get_resp_header(conn, "vary")
      assert vary =~ "authorization"
    end

    test "token for another shape is rejected", ctx do
      conn = ctx.conn |> with_bearer(owner_session(ctx, "file")) |> get_shape("user_cards")

      assert %{"shape" => "user_card"} = json_response(conn, 401)
    end

    test "versions table needs its owning shape's session", ctx do
      conn =
        ctx.conn
        |> with_bearer(owner_session(ctx, "user_storage"))
        |> get_shape("user_storage_versions")

      assert conn.status == 200
    end

    test "file_chunk_status needs a file_chunk session", ctx do
      path = "/electric/v1/file_chunk_status?file_ids=#{FileId.generate()}"

      assert %{"shape" => "file_chunk"} = ctx.conn |> get(path) |> json_response(401)

      assert ctx.conn
             |> with_bearer(owner_session(ctx, "file_chunk"))
             |> get(path)
             |> json_response(200)
    end

    test "file_chunk download is gated", %{conn: conn} do
      conn = get(conn, "/electric/v1/file_chunk/f_none/0")

      assert %{"shape" => "file_chunk"} = json_response(conn, 401)
    end
  end

  defp owner_session(ctx, shape),
    do: open_read_session!(ctx.conn, ctx.owner_card.user_hash, shape, ctx.owner.sign_skey)

  describe "CORS preflight for gated one-shot reads" do
    for path <- ["/electric/v1/file_chunk/f_none/0", "/electric/v1/file_chunk_status"] do
      test "#{path} allows the Authorization header", %{conn: conn} do
        conn = preflight_with_authorization(conn, unquote(path))

        assert conn.status in [200, 204]
        assert [allowed] = get_resp_header(conn, "access-control-allow-headers")
        assert allowed |> String.downcase() |> String.contains?("authorization")
      end
    end
  end

  defp preflight_with_authorization(conn, path) do
    conn
    |> put_req_header("origin", "https://app.example")
    |> put_req_header("access-control-request-method", "GET")
    |> put_req_header("access-control-request-headers", "authorization")
    |> options(path)
  end

  defp get_shape(conn, table),
    do: get(conn, "/electric/v1/shapes", %{"table" => table, "offset" => "-1"})
end
