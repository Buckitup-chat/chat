defmodule ChatWeb.SystemIdentifierControllerTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase
  import Rewire

  alias Chat.AdminDb

  defmodule MockOwnerNil do
    def owner, do: nil
  end

  defmodule MockOwnerPresent do
    def owner, do: %{user_hash: "test", sign_pkey: "test"}
  end

  setup do
    CubDB.delete(AdminDb.db(), :pq_admin)
    on_exit(fn -> CubDB.delete(AdminDb.db(), :pq_admin) end)
    :ok
  end

  test "returns 503 when device has no admin", %{conn: conn} do
    controller =
      rewire(ChatWeb.SystemIdentifierController, OwnerBootstrap: MockOwnerNil)

    conn = controller.show(conn, %{})

    assert conn.status == 503
    assert %{"error" => "device not activated"} = Jason.decode!(conn.resp_body)
  end

  test "returns system identifier when admin present", %{conn: conn} do
    controller =
      rewire(ChatWeb.SystemIdentifierController, OwnerBootstrap: MockOwnerPresent)

    conn = controller.show(conn, %{})

    assert conn.status == 200
    assert %{"system_identifier" => id} = Jason.decode!(conn.resp_body)
    assert is_binary(id)
  end
end
