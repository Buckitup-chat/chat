defmodule ChatWeb.MainLive.Page.AdminPanelRouterEventsTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.{AdminDb, Db, Dialogs, Identity, Rooms, User}
  alias Chat.Db.ChangeTracker
  alias Chat.User.UsersBroker
  alias ChatWeb.MainLive.Page.AdminPanel
  alias Phoenix.PubSub

  @to_platform "chat->platform"

  setup do
    CubDB.clear(AdminDb.db())
    CubDB.clear(Db.db())
    UsersBroker.sync()
    PubSub.subscribe(Chat.PubSub, @to_platform)
  end

  describe "platform requests" do
    test "wifi-submit trims credentials and asks platform to set them", %{conn: conn} do
      view = open_admin(conn)

      render_hook(view, "admin/wifi-submit", %{"ssid" => " home ", "password" => " secret "})

      assert_receive {:set_wifi, "home", "secret"}
      assert %{wifi_ssid: "home", wifi_password: "secret", wifi_loaded: false} = assigns(view)
    end

    test "device-log, unmount-main and gpio24 toggle are forwarded", %{conn: conn} do
      view = open_admin(conn)

      render_hook(view, "admin/device-log", %{})
      assert_receive :get_device_log

      render_hook(view, "admin/unmount-main", %{})
      assert_receive :unmount_main

      render_hook(view, "admin/toggle-gpio24-impendance", %{})
      assert_receive :toggle_gpio24_impendance
    end
  end

  describe "user and room management" do
    test "invites a user to the admin room through the confirmation modal", %{conn: conn} do
      bob = registered_user("Bob")
      view = open_admin(conn)

      assert render_hook(view, "admin/show-user-invite-modal", %{"hash" => hex(bob)}) =~
               "to the admin room?"

      assert_modal_transition(view, "show")
      render_hook(view, "admin/confirm-user-invite", %{"hash" => hex(bob)})
      assert_modal_transition(view, "hide")

      %{me: me} = assigns(view)
      dialog = Dialogs.find_or_open(me, User.by_id(Identity.pub_key(bob)))

      assert [_invite] = Dialogs.list_room_invites(dialog, me)
    end

    test "confirming an unknown user only closes the modal", %{conn: conn} do
      view = open_admin(conn)
      %{me: me} = assigns(view)
      ghost = User.login("Ghost")

      render_hook(view, "admin/confirm-user-invite", %{"hash" => hex(ghost)})

      assert_modal_transition(view, "hide")
      refute User.by_id(Identity.pub_key(ghost))
      assert Dialogs.find_or_open(me) |> Dialogs.list_room_invites(me) == []
    end

    test "remove-user deletes the user", %{conn: conn} do
      bob = registered_user("Bob")
      view = open_admin(conn)

      render_hook(view, "admin/remove-user", %{"hash" => hex(bob)})
      ChangeTracker.await()

      refute User.by_id(Identity.pub_key(bob))
    end

    test "remove-room deletes the room", %{conn: conn} do
      view = open_admin(conn)
      {room_identity, _room} = Rooms.add(assigns(view).me, "Doomed room")
      ChangeTracker.await()

      render_hook(view, "admin/remove-room", %{"hash" => hex(room_identity)})
      ChangeTracker.await()

      refute Rooms.get(Identity.pub_key(room_identity))
    end
  end

  describe "firmware upgrade" do
    test "upgrade confirmations close their modals", %{conn: conn} do
      view = open_admin(conn)

      send(view.pid, {:admin, :upgrade_firmware_confirmation})
      assert render(view) =~ "Upgrade firmware?"
      assert_modal_transition(view, "show")

      render_hook(view, "admin/upgrade-firmware", %{})
      assert_modal_transition(view, "hide")

      send(view.pid, {:admin, {:github_upgrade_firmware_confirmation, %{tag: "v9.9.9"}}})
      assert render(view) =~ "Download and install firmware v9.9.9?"
      assert_modal_transition(view, "show")

      render_hook(view, "admin/github-upgrade-firmware", %{})
      assert_modal_transition(view, "hide")
    end
  end

  describe "AdminPanel helpers outside the router" do
    test "int/1 marks the socket as needing login" do
      socket = AdminPanel.int(%Phoenix.LiveView.Socket{})

      assert %{need_login: true, handshaked: false} = socket.assigns
    end

    test "stop_poller/0 stops the free spaces poller and is idempotent", %{conn: conn} do
      open_admin(conn)
      assert Process.whereis(Chat.Db.FreeSpacesPoller)

      AdminPanel.stop_poller()

      refute Process.whereis(Chat.Db.FreeSpacesPoller)
      assert AdminPanel.stop_poller() == nil
    end
  end

  # Helpers

  defp open_admin(conn) do
    %{view: view} = prepare_view(%{conn: conn})
    view |> element(".navbar button", "Admin") |> render_click()
    view
  end

  defp assigns(view), do: reload_view(%{view: view}).socket.assigns

  defp registered_user(name) do
    name
    |> User.login()
    |> tap(&User.register/1)
    |> tap(&UsersBroker.put/1)
    |> tap(fn _ -> ChangeTracker.await() end)
  end

  defp assert_modal_transition(view, op) do
    assert_push_event(view, "js-event", %{data: data})
    assert [[^op, %{"to" => "#modal"}] | _] = Jason.decode!(data)
  end

  defp hex(identity), do: identity |> Identity.pub_key() |> Base.encode16(case: :lower)
end
