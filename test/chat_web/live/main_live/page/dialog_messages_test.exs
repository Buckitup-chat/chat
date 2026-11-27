defmodule ChatWeb.MainLive.Page.DialogMessagesTest do
  use ChatWeb.ConnCase, async: true, group: :cubdb

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest
  import Support.RetryHelper

  alias Chat.Dialogs

  @wait 3_000

  describe "text messages" do
    setup [:prepare_view, :open_dialog]

    test "blank text is not sent", %{view: view, socket: socket} do
      view |> form("#dialog-form", dialog: %{text: "   "}) |> render_submit()

      assert [] = read_messages(socket)
    end

    test "edit, update and cancel edit", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "first version")

      render_hook(view, "dialog/message/edit", msg_params(id, index))

      assert %{input_mode: :edit, edit_content: "first version", edit_message_id: {^index, ^id}} =
               assigns(view)

      assert_push_event(view, "chat:focus", %{to: "#dialog-edit-input"})

      render_hook(view, "dialog/edited-message", %{"dialog_edit" => %{"text" => "second version"}})

      assert %{input_mode: :plain, edit_content: nil, edit_message_id: nil} = assigns(view)

      retry_until(@wait, fn ->
        assert [%{id: ^id, content: "second version"}] = read_messages(socket)
      end)

      assert_push_event(view, "chat:change", %{to: to, content: content}, @wait)
      assert to == "#dialog-message-#{id} .x-content"
      assert content =~ ~S(data-name="LinkedText")

      render_hook(view, "dialog/message/edit", msg_params(id, index))
      render_hook(view, "dialog/cancel-edit", %{})

      assert %{input_mode: :plain, edit_content: nil, edit_message_id: nil} = assigns(view)
    end

    test "delete selected messages hides them", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "to delete")

      render_hook(view, "dialog/toggle-messages-select", %{"action" => "on"})
      assert %{input_mode: :select} = assigns(view)
      assert_push_event(view, "chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      render_hook(view, "dialog/delete-messages", %{
        "messages" => Jason.encode!([msg_params(id, index)])
      })

      assert %{input_mode: :plain} = assigns(view)
      assert_push_event(view, "chat:toggle", %{to: to, class: "hidden"}, @wait)
      assert to == "#message-block-#{id}"
      retry_until(@wait, fn -> assert [] = read_messages(socket) end)
    end

    test "select mode toggles off and survives loading more", %{view: view} do
      render_hook(view, "dialog/toggle-messages-select", %{"action" => "on"})
      render_hook(view, "chat:load-more", %{})

      assert %{input_mode: :select, page: 1} = assigns(view)
      assert_push_event(view, "chat:toggle", %{to: "#chat-messages", class: "selectMode"})

      render_hook(view, "dialog/toggle-messages-select", %{"action" => "off"})
      assert %{input_mode: :plain} = assigns(view)

      render_hook(view, "chat:load-more", %{})
      assert %{input_mode: :plain, page: 2} = assigns(view)
    end

    test "downloading a text message does nothing", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "not a file")

      render_hook(view, "dialog/message/download", msg_params(id, index))

      refute_push_event(view, "chat:redirect", %{})
    end

    test "show link opens the chat link modal", %{view: view} do
      render_hook(view, "dialog/show-link", %{"hash" => "abc123"})

      assert %{live_modal: %{params: %{url: url, encoded_qr_code: _}}} = assigns(view)
      assert url =~ "/trusted/chat/abc123"
    end

    test "close drops the dialog", %{view: view} do
      render_hook(view, "dialog/close", %{})

      assert %{dialog: nil, messages: nil, peer: nil} = assigns(view)
    end
  end

  describe "room invites in my notes" do
    setup [:prepare_view, :create_and_open_room, :switch_to_chats, :open_dialog]

    test "accepting an invite for a known room keeps the socket", %{view: view, socket: socket} do
      %{id: id, index: index} = await_invite(socket)

      render_hook(view, "dialog/message/accept-room-invite", msg_params(id, index))

      assert %{dialog: %{}} = assigns(view)
    end

    test "accept and open a known room", %{view: view, socket: socket} do
      %{id: id, index: index} = await_invite(socket)
      %{room_map: room_map} = assigns(view)

      render_hook(view, "dialog/message/accept-room-invite-and-open-room", msg_params(id, index))

      assert %{dialog: nil, room: %{pub_key: pub_key}, room_map: ^room_map} = assigns(view)
      assert Map.has_key?(room_map, pub_key)
    end

    test "accept all invites", %{view: view, socket: socket} do
      await_invite(socket)

      render_hook(view, "dialog/message/accept-all-room-invites", %{})

      assert %{dialog: %{}} = assigns(view)
    end

    test "accept and open on a non-invite message is ignored", %{view: view, socket: socket} do
      await_invite(socket)
      %{id: id, index: index} = send_and_await(view, socket, "plain text", 2)

      render_hook(view, "dialog/message/accept-room-invite-and-open-room", msg_params(id, index))

      assert %{dialog: %{}} = assigns(view)
    end
  end

  # Helpers

  defp switch_to_chats(%{view: view}) do
    render_hook(view, "switch-lobby-mode", %{"lobby-mode" => "chats"})
    reload_view(%{view: view})
  end

  defp assigns(view), do: reload_view(%{view: view}).socket.assigns

  defp msg_params(id, index), do: %{"id" => id, "index" => Integer.to_string(index)}

  defp read_messages(%{assigns: %{dialog: dialog, me: me}}), do: Dialogs.read(dialog, me)

  defp send_and_await(view, socket, text, count \\ 1) do
    view |> form("#dialog-form", dialog: %{text: text}) |> render_submit()

    retry_until(@wait, fn -> assert count == socket |> read_messages() |> length() end)

    socket |> read_messages() |> List.last()
  end

  defp await_invite(socket) do
    retry_until(@wait, fn -> assert [%{type: :room_invite}] = read_messages(socket) end)

    socket |> read_messages() |> List.first()
  end
end
