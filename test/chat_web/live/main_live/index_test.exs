defmodule ChatWeb.MainLive.IndexTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.{Card, Dialogs, Identity, Rooms, User}
  alias Chat.Dialogs.PrivateMessage
  alias Chat.Rooms.RoomsBroker
  alias Chat.User.UsersBroker

  describe "room sync between multiple tabs" do
    setup [:current_tab, :another_tab]

    defp current_tab(%{conn: _} = conn), do: [current_tab: login_by_key(conn)]
    defp another_tab(%{conn: _} = conn), do: [another_tab: login_by_key(conn)]

    test "on create", %{current_tab: current_tab, another_tab: another_tab} do
      %{view: current_tab_view} = current_tab
      %{view: another_tab_view} = another_tab

      %{socket: %{assigns: %{room_identity: room_identity}}} =
        create_and_open_room(%{view: current_tab_view})

      render_hook(current_tab_view, "room/sync-stored", %{
        "key" => Identity.priv_key_to_string(room_identity),
        "room_count" => 1
      })

      %{socket: %{assigns: current_view_state}} = reload_view(%{view: current_tab_view})
      %{socket: %{assigns: another_view_state}} = reload_view(%{view: another_tab_view})

      assert current_view_state.joined_rooms == another_view_state.joined_rooms
      assert current_view_state.room_count_to_backup == another_view_state.room_count_to_backup
    end

    test "on accepting the invitation", %{
      current_tab: current_tab,
      another_tab: another_tab,
      conn: conn
    } do
      %{view: current_tab_view, socket: %{assigns: %{me: me}}} = current_tab
      %{view: another_tab_view} = another_tab

      %{view: inviter_view, socket: %{assigns: %{room_identity: room_identity, me: inviter}}} =
        prepare_view(%{conn: conn}) |> create_and_open_room("private")

      my_hash = me |> Card.from_identity() |> then(& &1.hash)
      inviter_view |> element("#roomInviteButton") |> render_click()
      inviter_view |> element("#user-#{my_hash} a") |> render_click()

      inviter_hash = inviter |> Card.from_identity() |> then(& &1.hash)
      current_tab_view |> element("#dialog-list li#user-#{inviter_hash}") |> render_click()

      Support.RetryHelper.retry_until(2000, fn ->
        html = render(current_tab_view)

        if html =~ "acceptInviteButton" do
          current_tab_view |> element(".acceptInviteButton") |> render_click()
        else
          # Force a failure to trigger retry
          flunk("acceptInviteButton not found yet, retrying...")
        end
      end)

      render_hook(current_tab_view, "room/sync-stored", %{
        "key" => Identity.priv_key_to_string(room_identity),
        "room_count" => 1
      })

      %{socket: %{assigns: current_view_state}} = reload_view(%{view: current_tab_view})
      %{socket: %{assigns: another_view_state}} = reload_view(%{view: another_tab_view})

      assert current_view_state.joined_rooms == another_view_state.joined_rooms
      assert current_view_state.room_count_to_backup == another_view_state.room_count_to_backup
    end
  end

  describe "search box filtering" do
    setup [:create_users, :prepare_view, :create_rooms]

    test "search dialogs and rooms by name", %{view: view} do
      view |> form("#search-box", dialog: %{name: "pe"}) |> render_change()
      %{socket: %{assigns: %{users: users}}} = reload_view(%{view: view})
      assert match?([%{name: "Pedro"}, %{name: "Perky"}, %{name: "Peter"} | _], users)

      view
      |> element(
        "button[phx-click='switch-lobby-mode'][phx-value-lobby-mode='rooms']:first-child"
      )
      |> render_click()

      view |> form("#search-box", room: %{name: "Public"}) |> render_change()
      %{socket: %{assigns: %{new_rooms: rooms}}} = reload_view(%{view: view})
      names_set = rooms |> Enum.map(& &1.name) |> MapSet.new()
      assert ["Public1", "Public2", "Public3"] |> MapSet.new() |> MapSet.subset?(names_set)
    end

    defp create_users(_) do
      ["Peter", "Pedro", "Perky", "Olexandr", "Olexii"]
      |> Enum.each(fn name ->
        User.login(name)
        |> tap(&User.register/1)
        |> tap(&UsersBroker.put/1)
      end)
    end

    defp create_rooms(%{socket: %{assigns: %{me: me}}}) do
      ["Public1", "Public2", "Public3", "Secret1", "Secret2"]
      |> Enum.each(fn name ->
        Rooms.add(me, name) |> tap(fn {_, room} -> RoomsBroker.put(room) end)
      end)
    end
  end

  describe "downloading messages" do
    setup [:prepare_view, :open_dialog]

    test "one at a time", %{conn: conn, view: view} do
      %{socket: socket} = upload_file!(conn, view)

      %PrivateMessage{} =
        message =
        socket.assigns.dialog
        |> Dialogs.read(socket.assigns.me)
        |> List.first()

      render_hook(view, "dialog/message/download", %{
        "id" => message.id,
        "index" => Integer.to_string(message.index)
      })

      assert_push_event(view, "chat:redirect", %{url: url})

      conn = get(conn, url)

      assert conn.status == 200
      assert conn.resp_body =~ "1234"
    end

    test "multiple at once", %{conn: conn, view: view} do
      %{socket: _socket} = upload_file!(conn, view)

      # Submit the form with our test message
      view
      |> form("#dialog-form", %{"dialog" => %{"text" => "Dialog message text"}})
      |> render_submit()

      # Give Vue components time to render properly
      # Check for message text using the Vue component helper
      assert wait_until(
               fn ->
                 has_vue_content?(view, "LinkedText", "Dialog message text")
               end,
               "Message should appear in UI",
               timeout: 1000,
               interval: 50
             ) == :ok,
             "Message text should be displayed in the UI"

      # Log success message
      IO.puts("\nMessage successfully rendered in Vue component")

      # Load necessary data for download functionality
      new_socket = reload_view(%{view: view}).socket

      # Prepare messages for download without assertions on DB content
      messages_json =
        new_socket.assigns.dialog
        |> Dialogs.read(new_socket.assigns.me)
        |> Enum.map(fn %PrivateMessage{} = message ->
          %{"id" => message.id, "index" => Integer.to_string(message.index)}
        end)
        |> Jason.encode!()

      render_hook(view, "dialog/download-messages", %{"messages" => messages_json})

      assert_push_event(view, "chat:redirect", %{url: url})

      conn = get(conn, url)

      assert conn.status == 200
      assert conn.resp_body =~ "Created by Zstream"
    end
  end

  defp upload_file!(conn, view) do
    %{file: file, filename: filename, socket: socket} = start_upload(%{view: view})

    {key, _secret} =
      socket.assigns.uploads_metadata
      |> Enum.to_list()
      |> List.first()
      |> elem(1)
      |> Map.get(:credentials)

    %{status: 200} =
      conn
      |> put_req_header("content-length", "4")
      |> put_req_header("content-range", "bytes 0-3/4")
      |> put_req_header("content-type", "text/plain")
      |> put("/upload_chunk/#{Base.encode16(key, case: :lower)}", IO.iodata_to_binary("1234"))

    render_upload(file, filename, 100)

    %{socket: socket}
  end
end
