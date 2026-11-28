defmodule ChatWeb.MainLive.IndexCargoRoomSyncTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers
  import ChatWeb.LiveTestHelpers.{Navigation, SyncRooms}
  import Phoenix.LiveViewTest

  alias Chat.Admin.MediaSettings
  alias Chat.{AdminRoom, Dialogs, Messages, RoomInviteIndex, Rooms}
  alias Chat.Sync.CargoRoom

  describe "cargo room sync" do
    setup %{conn: conn} do
      reset_sync_rooms()
      AdminRoom.store_media_settings(%MediaSettings{functionality: :cargo})
      prepare_view(%{conn: conn})
    end

    test "starts the flow on room creation", %{view: view} do
      open_rooms_tab(view)

      submit_room_form(view, "Cargo Room", "cargo")

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
      open_rooms_tab(view)

      submit_room_form(view, "Regular Room", "public")

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
      open_rooms_tab(view)

      submit_room_form(view, "Regular Room", "public")

      submit_room_form(view, "Regular Room", "public")

      assert has_element?(view, "span div.t-cargo-activate")
      html = render(view)
      refute html =~ "phx-click=\"cargo:activate\""
      assert html =~ "Room does not have a unique name"
    end

    test "starts the flow from platform", %{conn: conn} do
      AdminRoom.store_media_settings(%MediaSettings{functionality: :backup})

      %{view: view} = prepare_view(%{conn: conn})

      open_rooms_tab(view)

      %{socket: socket} = reload_view(%{view: view})
      me = socket.assigns.me

      {room_identity, room} = Rooms.add(me, "Regular Room", :public)

      submit_room_form(view, "Another Regular Room", "public")

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

      open_chats_tab(view)

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
      open_rooms_tab(view)

      submit_room_form(view, "Cargo Room", "cargo")

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
      open_rooms_tab(view)

      submit_room_form(view, "Cargo Room", "cargo")

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
end
