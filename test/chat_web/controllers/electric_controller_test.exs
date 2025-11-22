defmodule ChatWeb.ElectricControllerTest do
  use ChatWeb.ConnCase, async: true

  alias Chat.Data.Schemas.User
  alias Chat.Db

  test "GET /electric/v1/sync returns a valid sync response", %{conn: conn} do
    # Insert a sample user via Ecto so Electric can see it in Postgres
    repo = Db.repo()

    user = %User{name: "Alice", pub_key: <<1, 2, 3>>}
    {:ok, _} = repo.insert(user)

    conn = get(conn, "/electric/v1/sync", %{})

    assert conn.status in [200, 304]
    # Body format is defined by Phoenix.Sync / Electric; we just assert it's non-empty on 200
    if conn.status == 200 do
      assert byte_size(conn.resp_body) > 0
    end
  end

  test "POST /electric/v1/ingest returns 204", %{conn: conn} do
    conn = post(conn, "/electric/v1/ingest", %{})

    assert conn.status == 204
    assert conn.resp_body == ""
  end
end
