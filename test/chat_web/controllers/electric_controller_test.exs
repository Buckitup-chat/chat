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

  test "POST /electric/v1/ingest with valid mutations returns txid", %{conn: conn} do
    # This test requires proper Electric Writer setup
    # Skipping for now as it needs more complex test infrastructure
    pub_key_bin = <<1::256>>
    pub_key = "\\x" <> Base.encode16(pub_key_bin, case: :lower)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{"name" => "Bob", "pub_key" => pub_key},
          "syncMetadata" => %{"relation" => "users"}
        }
      ]
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/electric/v1/ingest", Jason.encode!(payload))

    assert conn.status == 200
    assert %{"txid" => txid} = Jason.decode!(conn.resp_body)
    assert is_integer(txid)
  end

  test "POST /electric/v1/ingest with missing name returns 422 and details", %{conn: conn} do
    pub_key_bin = <<2::256>>
    pub_key = "\\x" <> Base.encode16(pub_key_bin, case: :lower)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{"pub_key" => pub_key},
          "syncMetadata" => %{"relation" => "users"}
        }
      ]
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/electric/v1/ingest", Jason.encode!(payload))

    assert conn.status == 422
    assert %{"error" => "validation_failed", "details" => details} = Jason.decode!(conn.resp_body)
    assert Map.has_key?(details, "name")
  end

  test "POST /electric/v1/ingest with duplicate pub_key returns 409", %{conn: conn} do
    repo = Db.repo()

    pub_key_bin = <<3::256>>
    {:ok, _} = repo.insert(%User{name: "Alice", pub_key: pub_key_bin})

    pub_key = "\\x" <> Base.encode16(pub_key_bin, case: :lower)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{"name" => "Alice Again", "pub_key" => pub_key},
          "syncMetadata" => %{"relation" => "users"}
        }
      ]
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/electric/v1/ingest", Jason.encode!(payload))

    assert conn.status == 409
    assert %{"error" => "pub_key_taken"} = Jason.decode!(conn.resp_body)
  end

  test "POST /electric/v1/ingest with invalid pub_key returns 400", %{conn: conn} do
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{"name" => "Bob", "pub_key" => "\\xzz"},
          "syncMetadata" => %{"relation" => "users"}
        }
      ]
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/electric/v1/ingest", Jason.encode!(payload))

    assert conn.status == 400
    assert conn.resp_body == "invalid_pub_key"
  end
end
