defmodule ChatWeb.MainLive.IndexCargoRoomTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers
  import ChatWeb.LiveTestHelpers.{Navigation, SyncRooms}
  import Phoenix.LiveViewTest

  alias Chat.Admin.MediaSettings
  alias Chat.{AdminRoom, Identity, User}
  alias Chat.User.UsersBroker

  describe "cargo room" do
    setup do
      reset_sync_rooms()
      UsersBroker.sync()

      :ok
    end

    test "creation is enabled by media settings functionality option", %{conn: conn} do
      AdminRoom.store_media_settings(%MediaSettings{})
      %{view: view} = prepare_view(%{conn: conn})

      open_rooms_tab(view)

      assert has_element?(view, "#room-create-form")
      refute has_element?(view, ~S<input[name="room_input[type]"][value="cargo"]>)

      open_admin_panel(view)

      view
      |> form("#media_settings", %{"media_settings" => %{"functionality" => "cargo"}})
      |> render_submit()

      open_rooms_tab(view)

      assert has_element?(view, ~S<input[name="room_input[type]"][value="cargo"]>)
    end

    test "when name is duplicate it shows an error", %{conn: conn} do
      AdminRoom.store_media_settings(%MediaSettings{functionality: :cargo})
      %{view: view} = prepare_view(%{conn: conn})

      open_rooms_tab(view)

      submit_room_form(view, "Cargo Room", "cargo")

      assert submit_room_form(view, "Cargo Room", "cargo") =~ "has already been taken"
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

      open_admin_panel(view)

      view
      |> element("#users-rest")
      |> render_hook("move_user", %{"type" => "rest", "pub_key" => encoded_checkpoint_1_pub_key})

      view
      |> element("#users-rest")
      |> render_hook("move_user", %{"type" => "rest", "pub_key" => encoded_checkpoint_2_pub_key})

      open_rooms_tab(view)

      submit_room_form(view, "Cargo Room", "cargo")

      open_chats_tab(view)

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
end
