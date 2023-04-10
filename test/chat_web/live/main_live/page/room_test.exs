defmodule ChatWeb.MainLive.Page.RoomTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Rooms
  alias ChatWeb.MainLive.Modals.ShareMessageLink
  alias ChatWeb.MainLive.Modals.UnlinkMessages

  describe "room message links" do
    @msg_text "¡Hola!"
    setup [:login_by_key, :create_and_open_room, :create_and_link_message]

    test "link message and unlink all messages", %{view: view, socket: %{assigns: assigns}} do
      assert true = assigns.is_room_linked?

      assert %{component: ShareMessageLink, params: %{encoded_qr_code: _, url: _}} =
               assigns.live_modal

      %{view: view} = close_sharelink_modal(%{view: view})
      view |> element("#unlinkRoomLink a.block") |> render_click()
      %{view: view, socket: %{assigns: state}} = reload_view(%{view: view})

      assert %{component: UnlinkMessages, params: %{}} = state.live_modal

      view |> element("#modal button.confirmButton") |> render_click()
      %{view: view, socket: %{assigns: %{is_room_linked?: false}}} = reload_view(%{view: view})
    end

    test "go to room by active link", %{conn: conn, view: view, socket: %{assigns: assigns}} do
      %{room: %{pub_key: room_pub_key}} = assigns
      %{params: %{url: url}} = assigns.live_modal
      link_hash = url |> String.split("/") |> List.last()

      %{view: view} = close_sharelink_modal(%{view: view})

      %{view: view, socket: %{assigns: new_assigns}} =
        login_by_key(%{conn: conn}, "/room/" <> link_hash)

      assert "/" = assert_patch(view)
      assert room_pub_key = new_assigns.room.pub_key
      assert [room] = new_assigns.joined_rooms
      assert true = new_assigns.is_room_linked?

      %{messages: [msg]} = new_assigns
      assert view |> element("#message-block-#{msg.id}") |> render() =~ @msg_text
    end

    test "404 if link is canceled or non-existed", %{conn: conn} do
      link_hash = "randomULTRAMEGAPWERLINK12345"

      %{view: view, socket: %{assigns: assigns}} =
        login_by_key(%{conn: conn}, "/room/" <> link_hash)

      assert link_hash = assigns.room_message_link_hash
      assert [] = assigns.joined_rooms
      view |> element("#notFoundScreen") |> render()

      rendered = view |> element("#notFoundScreen") |> render()
      assert rendered =~ "4  0  4"
      assert rendered =~ "Not found"
      assert rendered =~ "Go back to the root"
    end

    defp create_and_link_message(%{view: view}) do
      view |> form("#room-form", room: %{text: @msg_text}) |> render_submit()
      %{view: view, socket: %{assigns: %{messages: [%{id: id}]}}} = reload_view(%{view: view})

      view |> element("#message-block-#{id} .t-link-action") |> render_click()
      reload_view(%{view: view})
    end

    defp close_sharelink_modal(%{view: view}) do
      view |> element("#modal a.phx-modal-close") |> render_click()

      reload_view(%{view: view})
    end
  end
end
