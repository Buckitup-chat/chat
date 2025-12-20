defmodule ChatWeb.MainLive.Modals.ShowChatLinkTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Phoenix.LiveViewTest
  import ChatWeb.LiveTestHelpers

  alias ChatWeb.MainLive.Modals.ShowChatLink

  describe "ShowChatLink component" do
    setup [:prepare_view]

    test "renders correctly with URL and QR code" do
      test_url = "https://example.com/chat/abc123"
      encoded_qr_code = "test_encoded_qr_code"

      # Render the component directly
      html =
        render_component(&ShowChatLink.render/1, %{
          id: "show-chat-link-modal",
          url: test_url,
          encoded_qr_code: encoded_qr_code,
          button_text: "Copy",
          myself: "show-chat-link-modal"
        })

      # Verify the component content
      assert html =~ "Chat link"
      assert html =~ test_url
      assert html =~ encoded_qr_code
      assert html =~ "Copy"
    end

    test "handle_event copy changes button_text to Copied" do
      # Create a proper LiveView socket for testing
      socket = %Phoenix.LiveView.Socket{
        assigns: %{button_text: "Copy", __changed__: %{}},
        endpoint: ChatWeb.Endpoint
      }

      # Call the handle_event function
      {:noreply, updated_socket} = ShowChatLink.handle_event("copy", %{}, socket)

      # Verify the result
      assert updated_socket.assigns.button_text == "Copied"
    end

    test "QR code is displayed as an image" do
      test_url = "https://example.com/chat/abc123"
      encoded_qr_code = "test_encoded_qr_code"

      # Render the component directly
      html =
        render_component(&ShowChatLink.render/1, %{
          id: "show-chat-link-modal",
          url: test_url,
          encoded_qr_code: encoded_qr_code,
          button_text: "Copy",
          myself: "show-chat-link-modal"
        })

      # Verify the QR code image is rendered correctly
      assert html =~ ~s(src="data:image/svg+xml;base64, #{encoded_qr_code}")
      assert html =~ ~s(<a href="#{test_url}")
    end
  end
end
