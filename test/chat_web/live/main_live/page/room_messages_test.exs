defmodule ChatWeb.MainLive.Page.RoomMessagesTest do
  use ChatWeb.ConnCase, async: true, group: :cubdb

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest
  import Support.RetryHelper

  alias Chat.Card
  alias Chat.Rooms
  alias ChatWeb.MainLive.Modals.RoomInviteList

  @wait 3_000

  describe "room messages" do
    setup [:prepare_view, :create_and_open_room]

    test "blank text is not sent", %{view: view, socket: socket} do
      view |> form("#room-form", room: %{text: "  "}) |> render_submit()

      assert [] = read_messages(socket)
    end

    test "edit, update and cancel edit", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "first version")

      render_hook(view, "room/message/edit", msg_params(id, index))

      assert %{input_mode: :edit, edit_content: "first version", edit_message_id: {^index, ^id}} =
               assigns(view)

      assert_push_event(view, "chat:focus", %{to: "#room-edit-input"})

      render_hook(view, "room/edited-message", %{"room_edit" => %{"text" => "second version"}})

      assert %{input_mode: :plain, edit_content: nil, edit_message_id: nil} = assigns(view)
      assert_push_event(view, "chat:change", %{to: to, content: content}, @wait)
      assert to == "#room-message-#{id} .x-content"
      assert content =~ ~S(data-name="LinkedText")
      assert [%{id: ^id, content: "second version"}] = read_messages(socket)

      render_hook(view, "room/message/edit", msg_params(id, index))
      render_hook(view, "room/cancel-edit", %{})

      assert %{input_mode: :plain, edit_content: nil, edit_message_id: nil} = assigns(view)
    end

    test "delete selected messages hides them", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "to delete")

      render_hook(view, "room/toggle-messages-select", %{"action" => "on"})
      assert %{input_mode: :select} = assigns(view)

      render_hook(view, "room/delete-messages", selected(id, index))

      assert %{input_mode: :plain} = assigns(view)
      assert_push_event(view, "chat:toggle", %{to: to, class: "hidden"}, @wait)
      assert to == "#message-block-#{id}"
      retry_until(@wait, fn -> assert [] = read_messages(socket) end)
    end

    test "download selected messages redirects to a zip", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "zip me")

      render_hook(view, "room/download-messages", selected(id, index))

      assert_push_event(view, "chat:redirect", %{url: "/get/zip/" <> _})
    end

    test "downloading a text message does nothing", %{view: view, socket: socket} do
      %{id: id, index: index} = send_and_await(view, socket, "not a file")

      render_hook(view, "room/message/download", msg_params(id, index))

      refute_push_event(view, "chat:redirect", %{})
    end

    test "image message download redirects to the image", %{
      conn: conn,
      view: view,
      socket: socket
    } do
      upload_image(conn, view)

      retry_until(@wait, fn -> assert [%{type: :image}] = read_messages(socket) end)
      [%{id: id, index: index}] = read_messages(socket)

      render_hook(view, "room/message/download", msg_params(id, index))

      assert_push_event(view, "chat:redirect", %{url: "/get/image/" <> query})
      assert query =~ "download=true"
    end

    test "select mode survives loading more and new messages", %{view: view} do
      render_hook(view, "room/toggle-messages-select", %{"action" => "on"})
      render_hook(view, "chat:load-more", %{})

      assert %{input_mode: :select, page: 1} = assigns(view)

      send(view.pid, {:room, :load_new_messages})

      assert_push_event(view, "chat:scroll-down", %{})
      assert %{input_mode: :select, message_update_mode: :append} = assigns(view)

      render_hook(view, "room/toggle-messages-select", %{"action" => "off"})
      send(view.pid, {:room, :load_new_messages})

      assert %{input_mode: :plain} = assigns(view)
    end

    test "switching to an unknown room keeps it closed", %{view: view} do
      render_hook(view, "room/switch", %{"room" => String.duplicate("ab", 33)})

      assert %{room: nil, room_identity: nil} = assigns(view)
    end

    test "invite list lists other users", %{conn: conn, view: view} do
      prepare_view(%{conn: conn}, "Invitee")

      render_hook(view, "room/open-invite-list", %{})

      assert %{live_modal: %{component: RoomInviteList, params: %{users: [_ | _]}}} =
               assigns(view)
    end
  end

  defp msg_params(id, index), do: %{"id" => id, "index" => Integer.to_string(index)}

  defp read_messages(%{assigns: %{room: room, room_identity: identity}}),
    do: Rooms.read(room, identity)

  defp upload_image(conn, view) do
    %{file: file, filename: filename, socket: socket} = start_upload(%{view: view})
    [%{credentials: {key, _secret}}] = Map.values(socket.assigns.uploads_metadata)

    conn
    |> put_req_header("content-length", "4")
    |> put_req_header("content-range", "bytes 0-3/4")
    |> put_req_header("content-type", "text/plain")
    |> put("/upload_chunk/#{Base.encode16(key, case: :lower)}", "1234")
    |> then(&assert &1.status == 200)

    render_upload(file, filename, 100)
  end

  defp selected(id, index), do: %{"messages" => Jason.encode!([msg_params(id, index)])}

  defp send_and_await(view, socket, text) do
    view |> form("#room-form", room: %{text: text}) |> render_submit()

    retry_until(@wait, fn -> assert [_] = read_messages(socket) end)

    socket |> read_messages() |> List.last()
  end

  describe "request room" do
    setup %{conn: conn} do
      %{view: owner_view, socket: owner_socket} =
        %{conn: conn} |> prepare_view("Owner") |> create_and_open_room("request")

      %{view: requester_view, socket: %{assigns: %{me: requester}}} =
        prepare_view(%{conn: conn}, "Requester")

      %{
        owner_view: owner_view,
        owner_socket: owner_socket,
        requester_view: requester_view,
        requester: requester
      }
    end

    test "owner sees the request and approves it", %{
      owner_view: owner_view,
      owner_socket: %{assigns: %{room: room}},
      requester_view: requester_view,
      requester: requester
    } do
      %{pub_key: requester_key} = Card.from_identity(requester)
      room_hash = Base.encode16(room.pub_key, case: :lower)

      render_hook(requester_view, "room/send-request", %{"room" => room_hash})
      render_hook(owner_view, "room/switch", %{"room" => room_hash})

      assert [%{pub_key: ^requester_key}] = assigns(owner_view).room_requests

      render_hook(owner_view, "room/approve-request", %{
        "hash" => Base.encode16(requester_key, case: :lower)
      })

      assert %{room_requests: [], room_requests_update_mode: "ignore"} = assigns(owner_view)
      assert_push_event(owner_view, "put-flash", %{key: :info, message: "Request approved!"})
    end
  end

  # Helpers

  defp assigns(view), do: reload_view(%{view: view}).socket.assigns
end
