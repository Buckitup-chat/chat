defmodule ChatWeb.MainLive.Modals.ConfirmInviteToAdminRoomTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ChatWeb.LiveTestHelpers

  alias Chat.Card
  alias Chat.Identity
  alias ChatWeb.MainLive.Modals.ConfirmInviteToAdminRoom

  describe "ConfirmInviteToAdminRoom component" do
    setup [:prepare_view, :create_test_user]

    test "renders correctly with user information", %{test_user: test_user} do
      # Render the component directly
      html =
        render_component(&ConfirmInviteToAdminRoom.render/1, %{
          id: "confirm-invite-modal",
          user: test_user
        })

      # Verify the component content
      assert html =~ "Invite new one"
      assert html =~ "Are you sure you want to invite"
      assert html =~ test_user.hash
      assert html =~ "Cancel"
      assert html =~ "Ok"
    end
  end

  # Helper functions
  defp create_test_user(%{conn: _conn}) do
    # Create a test identity
    test_identity = Identity.create("Test User")
    test_card = Card.from_identity(test_identity)

    [test_user: test_card]
  end
end
