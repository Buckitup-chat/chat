defmodule ChatWeb.MainLive.IndexTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Admin.MediaSettings
  alias Chat.{AdminDb, AdminRoom, Card, Db, Dialogs, Rooms, User}
  alias Chat.Dialogs.PrivateMessage
  alias Chat.{Identity, Messages, RoomInviteIndex}
  alias Chat.Rooms.RoomsBroker
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}
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
      %{socket: socket} = upload_file(conn, view)

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
      %{socket: socket} = upload_file(conn, view)

      view
      |> form("#dialog-form", %{"dialog" => %{"text" => "Dialog message text"}})
      |> render_submit()

      assert has_element?(view, ".messageBlock", "Dialog message text")

      messages =
        socket.assigns.dialog
        |> Dialogs.read(socket.assigns.me)
        |> Enum.map(fn %PrivateMessage{} = message ->
          %{"id" => message.id, "index" => Integer.to_string(message.index)}
        end)
        |> Jason.encode!()

      render_hook(view, "dialog/download-messages", %{"messages" => messages})

      assert_push_event(view, "chat:redirect", %{url: url})

      conn = get(conn, url)

      assert conn.status == 200
      assert conn.resp_body =~ "Created by Zstream"
    end
  end

  describe "cargo room" do
    setup do
      AdminDb.db() |> CubDB.clear()
      Db.db() |> CubDB.clear()
      CargoRoom.remove()
      UsbDriveDumpRoom.remove()
      UsersBroker.sync()

      :ok
    end

    test "creation is enabled by media settings functionality option", %{conn: conn} do
      AdminRoom.store_media_settings(%MediaSettings{})
      %{view: view} = prepare_view(%{conn: conn})

      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      assert has_element?(view, "#room-create-form")
      refute has_element?(view, ~S<input[name="room_input[type]"][value="cargo"]>)

      view
      |> element(".navbar button", "Admin")
      |> render_click()

      view
      |> form("#media_settings", %{"media_settings" => %{"functionality" => "cargo"}})
      |> render_submit()

      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      assert has_element?(view, ~S<input[name="room_input[type]"][value="cargo"]>)
    end

    test "when name is duplicate it shows an error", %{conn: conn} do
      AdminRoom.store_media_settings(%MediaSettings{functionality: :cargo})
      %{view: view} = prepare_view(%{conn: conn})

      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{"room_input" => %{"name" => "Cargo Room", "type" => "cargo"}})
      |> render_submit()

      assert view
             |> form("#room-create-form", %{
               "room_input" => %{"name" => "Cargo Room", "type" => "cargo"}
             })
             |> render_submit() =~ "has already been taken"
    end

    @tag :skip
    # todo: explain
    # todo: migrate from dropdowns to select and button click
    test "sends invites to checkpoints in the preset after creation", %{conn: conn} do
      checkpoint_1 = User.login("Checkpoint 1")
      checkpoint_1 |> tap(&User.register/1) |> tap(&UsersBroker.put/1)

      checkpoint_1_key = checkpoint_1 |> Identity.pub_key()
      encoded_checkpoint_1_pub_key = checkpoint_1_key |> Base.encode16(case: :lower)

      checkpoint_2 = User.login("Checkpoint 2")
      checkpoint_2 |> tap(&User.register/1) |> tap(&UsersBroker.put/1)
      checkpoint_2_key = checkpoint_2 |> Identity.pub_key()
      encoded_checkpoint_2_pub_key = checkpoint_2_key |> Base.encode16(case: :lower)

      checkpoint_3 = User.login("Checkpoint 3")
      checkpoint_3 |> tap(&User.register/1) |> tap(&UsersBroker.put/1)

      AdminRoom.store_media_settings(%MediaSettings{functionality: :cargo})
      %{view: view} = prepare_view(%{conn: conn})

      view
      |> element(".navbar button", "Admin")
      |> render_click()

      view
      |> element("#users-rest")
      |> render_hook("move_user", %{"type" => "rest", "pub_key" => encoded_checkpoint_1_pub_key})

      view
      |> element("#users-rest")
      |> render_hook("move_user", %{"type" => "rest", "pub_key" => encoded_checkpoint_2_pub_key})

      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{"room_input" => %{"name" => "Cargo Room", "type" => "cargo"}})
      |> render_submit()

      view
      |> element(".t-chats", "Chats")
      |> render_click()

      view
      |> element("#chatRoomBar ul li.hidden", "Checkpoint 1")
      |> render_click()

      assert view
             |> element("#chatRoomBar ul li.hidden", "Checkpoint 1")
             |> render_click() =~ "is invited by you into"

      assert view
             |> element("#chatRoomBar ul li.hidden", "Checkpoint 2")
             |> render_click() =~ "is invited by you into"

      refute view
             |> element("#chatRoomBar ul li.hidden", "Checkpoint 3")
             |> render_click() =~ "is invited by you into"
    end
  end

  describe "cargo room sync" do
    setup %{conn: conn} do
      AdminDb.db() |> CubDB.clear()
      Db.db() |> CubDB.clear()
      CargoRoom.remove()
      UsbDriveDumpRoom.remove()
      AdminRoom.store_media_settings(%MediaSettings{functionality: :cargo})
      prepare_view(%{conn: conn})
    end

    test "starts the flow on room creation", %{view: view} do
      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Cargo Room", "type" => "cargo"}
      })
      |> render_submit()

      Process.sleep(100)

      refute has_element?(view, ".t-cargo-room")
      refute has_element?(view, "span div.t-cargo-activate")
      assert has_element?(view, ".t-cargo-remove")
      html = render(view)
      assert html =~ "Cargo sync activated"
      assert html =~ "Insert empty USB drive"

      %{socket: socket} = reload_view(%{view: view})
      CargoRoom.sync(socket.assigns.room.pub_key)
      Process.sleep(100)

      assert render(view) =~ "Syncing..."
      refute has_element?(view, ".t-cargo-remove")

      CargoRoom.mark_successful()
      CargoRoom.complete()
      Process.sleep(100)

      assert render(view) =~ "Complete!"
      assert has_element?(view, ".t-cargo-room")
      assert has_element?(view, ".t-cargo-remove")

      view
      |> element(".t-cargo-remove")
      |> render_click()

      refute has_element?(view, ".t-cargo-room")
      refute render(view) =~ "Cargo sync activated"
    end

    test "starts the flow in existing room", %{view: view} do
      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Regular Room", "type" => "public"}
      })
      |> render_submit()

      refute has_element?(view, ".t-cargo-room")
      assert has_element?(view, "span div.t-cargo-activate")

      view
      |> element("span div.t-cargo-activate")
      |> render_click()

      refute has_element?(view, ".t-cargo-room")
      refute has_element?(view, "span div.t-cargo-activate")
      assert has_element?(view, ".t-cargo-remove")
      html = render(view)
      assert html =~ "Cargo sync activated"
      assert html =~ "Insert empty USB drive"
    end

    test "is disabled for rooms with non-unique names", %{view: view} do
      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Regular Room", "type" => "public"}
      })
      |> render_submit()

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Regular Room", "type" => "public"}
      })
      |> render_submit()

      assert has_element?(view, "span div.t-cargo-activate")
      html = render(view)
      refute html =~ "phx-click=\"cargo:activate\""
      assert html =~ "Room does not have a unique name"
    end

    test "starts the flow from platform", %{conn: conn} do
      AdminRoom.store_media_settings(%MediaSettings{functionality: :backup})

      %{view: view} = prepare_view(%{conn: conn})

      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      %{socket: socket} = reload_view(%{view: view})
      me = socket.assigns.me

      {room_identity, room} = Rooms.add(me, "Regular Room", :public)

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Another Regular Room", "type" => "public"}
      })
      |> render_submit()

      refute has_element?(view, ".t-cargo-room")
      refute has_element?(view, "span div.t-cargo-activate")

      CargoRoom.sync(room.pub_key)
      Process.sleep(100)

      refute has_element?(view, ".t-cargo-room")
      refute has_element?(view, "span div.t-cargo-activate")
      refute has_element?(view, ".t-cargo-remove")
      refute render(view) =~ "Cargo sync activated"

      CargoRoom.mark_successful()
      CargoRoom.complete()
      Process.sleep(100)

      refute has_element?(view, ".t-cargo-room")
      refute has_element?(view, "span div.t-cargo-activate")
      refute has_element?(view, ".t-cargo-remove")
      refute render(view) =~ "Cargo sync activated"

      dialog = Dialogs.find_or_open(me)

      room_identity
      |> Map.put(:name, room.name)
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(me, dialog)
      |> RoomInviteIndex.add(dialog, me, room.pub_key)

      view
      |> element(".t-chats", "Chats")
      |> render_click()

      open_dialog(%{view: view})

      view
      |> element("button:first-child", "Accept")
      |> render_click()

      assert has_element?(view, ".t-cargo-room")

      view
      |> element(".t-cargo-room", "Cargo Room")
      |> render_click()

      refute has_element?(view, "span div.t-cargo-activate")
      assert has_element?(view, ".t-cargo-remove")
      html = render(view)
      assert html =~ "Cargo sync activated"
      assert html =~ "Complete!"
    end

    test "fails syncing", %{view: view} do
      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Cargo Room", "type" => "cargo"}
      })
      |> render_submit()

      Process.sleep(100)

      assert render(view) =~ "Cargo sync activated"

      %{socket: socket} = reload_view(%{view: view})
      CargoRoom.sync(socket.assigns.room.pub_key)
      Process.sleep(100)

      assert render(view) =~ "Syncing..."

      CargoRoom.complete()
      Process.sleep(100)

      assert render(view) =~ "Failed!"
      refute has_element?(view, ".t-cargo-room")
      assert has_element?(view, ".t-cargo-remove")

      view
      |> element(".t-cargo-remove")
      |> render_click()

      refute has_element?(view, ".t-cargo-room")
      refute render(view) =~ "Cargo sync activated"
    end

    test "stops the process early", %{view: view} do
      view
      |> element(".t-rooms", "Rooms")
      |> render_click()

      view
      |> form("#room-create-form", %{
        "room_input" => %{"name" => "Cargo Room", "type" => "cargo"}
      })
      |> render_submit()

      Process.sleep(100)

      assert render(view) =~ "Cargo sync activated"
      assert has_element?(view, ".t-cargo-remove")

      view
      |> element(".t-cargo-remove")
      |> render_click()

      refute has_element?(view, ".t-cargo-room")
      refute render(view) =~ "Cargo sync activated"

      view
      |> element("span div.t-cargo-activate")
      |> render_click()

      assert render(view) =~ "Cargo sync activated"

      CargoRoom.remove()

      Process.sleep(100)

      refute render(view) =~ "Cargo sync activated"
    end
  end

  defp upload_file(conn, view) do
    %{file: file, filename: filename, socket: socket} = start_upload(%{view: view})

    {key, _secret} =
      socket.assigns.uploads_metadata
      |> Enum.to_list()
      |> List.first()
      |> elem(1)
      |> Map.get(:credentials)

    upload_conn =
      conn
      |> put_req_header("content-length", "4")
      |> put_req_header("content-range", "bytes 0-3/4")
      |> put_req_header("content-type", "text/plain")
      |> put("/upload_chunk/#{Base.encode16(key, case: :lower)}", IO.iodata_to_binary("1234"))

    assert upload_conn.status == 200

    render_upload(file, filename, 100)

    %{socket: socket}
  end

  describe "usb drive dump" do
    setup %{conn: conn} do
      AdminDb.db() |> CubDB.clear()
      Db.db() |> CubDB.clear()
      CargoRoom.remove()
      UsbDriveDumpRoom.remove()

      %{conn: conn}
      |> prepare_view()
      |> create_and_open_room()
    end

    test "starts the flow in existing room", %{view: view} do
      refute has_element?(view, ".t-dump-room")
      assert has_element?(view, "span div.t-dump-activate")

      view
      |> element("span div.t-dump-activate")
      |> render_click()

      refute has_element?(view, ".t-dump-room")
      refute has_element?(view, "span div.t-dump-activate")
      assert has_element?(view, ".t-dump-remove")
      html = render(view)
      assert html =~ "USB drive dump activated"
      assert html =~ "Insert empty USB drive"
      assert String.contains?(html, "5:00") or String.contains?(html, "4:59")

      Process.sleep(1000)
      assert render(view) =~ ~r/4:5\d/

      UsbDriveDumpRoom.dump()
      Process.sleep(100)

      refute has_element?(view, ".t-dump-room")
      refute has_element?(view, "span div.t-dump-activate")
      refute has_element?(view, ".t-dump-remove")
      assert render(view) =~ "USB drive dump activated"

      UsbDriveDumpRoom.mark_successful()
      UsbDriveDumpRoom.complete()
      Process.sleep(100)

      assert has_element?(view, ".t-dump-room")
      refute has_element?(view, "span div.t-dump-activate")
      assert has_element?(view, ".t-dump-remove")
      html = render(view)
      assert html =~ "USB drive dump activated"
      assert html =~ "Complete!"

      view
      |> element(".t-dump-room", "Dump room")
      |> render_click()

      refute has_element?(view, "span div.t-dump-activate")
      assert has_element?(view, ".t-dump-remove")
      html = render(view)
      assert html =~ "USB drive dump activated"
      assert html =~ "Complete!"
    end

    test "fails dumping", %{view: view} do
      refute has_element?(view, ".t-dump-room")
      assert has_element?(view, "span div.t-dump-activate")

      view
      |> element("span div.t-dump-activate")
      |> render_click()

      assert render(view) =~ "USB drive dump activated"

      UsbDriveDumpRoom.dump()
      Process.sleep(100)

      assert render(view) =~ "Dumping..."

      UsbDriveDumpRoom.complete()
      Process.sleep(100)

      assert render(view) =~ "Failed!"
      refute has_element?(view, ".t-dump-room")
      assert has_element?(view, ".t-dump-remove")

      view
      |> element(".t-dump-remove")
      |> render_click()

      refute has_element?(view, ".t-dump-room")
      refute render(view) =~ "USB drive dump activated"
    end

    test "stops the process early", %{view: view} do
      view
      |> element("span div.t-dump-activate")
      |> render_click()

      assert render(view) =~ "USB drive dump activated"
      assert has_element?(view, ".t-dump-remove")

      view
      |> element(".t-dump-remove")
      |> render_click()

      refute has_element?(view, ".t-dump-room")
      refute render(view) =~ "USB drive dump activated"

      view
      |> element("span div.t-dump-activate")
      |> render_click()

      assert render(view) =~ "USB drive dump activated"

      UsbDriveDumpRoom.remove()

      Process.sleep(100)

      refute render(view) =~ "USB drive dump activated"
    end
  end
end
