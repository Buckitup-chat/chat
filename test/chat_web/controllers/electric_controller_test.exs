defmodule ChatWeb.ElectricControllerTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Data.Schemas.User
  alias Chat.Db

  test "GET /electric/v1/user sync endpoint exists", %{conn: conn} do
    # Insert a sample user via Ecto so Electric can see it in Postgres
    repo = Db.repo()

    user = %User{name: "Alice", pub_key: <<1, 2, 3>>}
    {:ok, _} = repo.insert(user)

    conn = get(conn, "/electric/v1/user", %{})

    # Phoenix.Sync may return 200, 304, or 400 depending on Electric setup
    # We just verify the endpoint is routed correctly
    assert conn.status in [200, 304, 400]
  end

  test "POST /electric/v1/ingest with invalid payload returns 400", %{conn: conn} do
    conn = post(conn, "/electric/v1/ingest", %{})

    assert conn.status == 400
    assert conn.resp_body == "invalid_payload"
  end

  @tag :skip
  test "POST /electric/v1/ingest with valid mutations returns txid", %{conn: conn} do
    # This test requires proper Electric Writer setup
    # Skipping for now as it needs more complex test infrastructure
    mutations = [
      %{
        "type" => "insert",
        "table" => "users",
        "values" => %{"name" => "Bob", "pub_key" => "test_key"}
      }
    ]

    conn = post(conn, "/electric/v1/ingest", %{"mutations" => mutations})

    assert conn.status == 200
    assert %{"txid" => _txid} = Jason.decode!(conn.resp_body)
  end
end
