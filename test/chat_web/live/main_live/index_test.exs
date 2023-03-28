defmodule ChatWeb.MainLive.IndexTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Admin.MediaSettings
  alias Chat.{AdminDb, AdminRoom, Db, Dialogs, User}
  alias Chat.Dialogs.PrivateMessage
  alias Chat.Identity

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

    test "sends invites to checkpoints in the preset after creation", %{conn: conn} do
      checkpoint_1 = User.login("Checkpoint 1")
      checkpoint_1 |> User.register()
      checkpoint_1_key = checkpoint_1 |> Identity.pub_key()
      encoded_checkpoint_1_pub_key = checkpoint_1_key |> Base.encode16(case: :lower)

      checkpoint_2 = User.login("Checkpoint 2")
      checkpoint_2 |> User.register()
      checkpoint_2_key = checkpoint_2 |> Identity.pub_key()
      encoded_checkpoint_2_pub_key = checkpoint_2_key |> Base.encode16(case: :lower)

      checkpoint_3 = User.login("Checkpoint 3")
      checkpoint_3 |> User.register()

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
end
