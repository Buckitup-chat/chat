defmodule ChatWeb.PlainControllerTest do
  use ChatWeb.ConnCase, async: true
  import Rewire

  # Define mock module for AdminRoom
  defmodule AdminRoomMock do
    def get_privacy_policy_text do
      "Privacy Policy Content"
    end
  end

  test "GET /privacy-policy.html returns privacy policy text", %{conn: conn} do
    # Create a module with the mocked dependency
    rewired_controller =
      rewire(ChatWeb.PlainController, [
        {Chat.AdminRoom, AdminRoomMock}
      ])

    # Call the controller function directly with the conn
    conn =
      conn
      |> rewired_controller.privacy_policy(%{})

    assert conn.status == 200
    assert conn.resp_body == "Privacy Policy Content"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end
end
