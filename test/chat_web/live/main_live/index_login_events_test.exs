defmodule ChatWeb.MainLive.IndexLoginEventsTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.User

  describe "restoreAuth with stored auth" do
    test "logs the stored user in", %{conn: conn} do
      me = User.login("Stored")
      {:ok, view, _html} = live(conn, "/trusted")

      render_hook(view, "restoreAuth", %{"auth" => User.device_encode(me), "room_count" => 2})

      %{socket: %{assigns: assigns}} = reload_view(%{view: view})
      assert assigns.me.public_key == me.public_key
      assert assigns.room_count_to_backup == 2
      refute assigns.need_login
    end

    test "ignores unrecognized auth data", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/trusted/export-key-ring/some-id")

      render_hook(view, "restoreAuth", %{"unexpected" => "data"})

      %{socket: %{assigns: assigns}} = reload_view(%{view: view})
      assert assigns.mode == :export_key_ring
      refute Map.has_key?(assigns, :me)
    end
  end

  describe "key ring export" do
    test "moves the key ring from the exporting tab to the importing one", %{conn: conn} do
      exporter = User.login("Exporter")
      {:ok, importer_view, _html} = live(conn, "/trusted")
      render_hook(importer_view, "restoreAuth")
      render_hook(importer_view, "login:request-key-ring")

      %{socket: %{assigns: %{url: url, code: code, mode: :import_key_ring}}} =
        reload_view(%{view: importer_view})

      {:ok, export_view, _html} = live(conn, URI.parse(url).path)
      render_hook(export_view, "restoreAuth", %{"auth" => User.device_encode(exporter)})
      render_hook(export_view, "client-timestamp", %{"timestamp" => 0})
      render_hook(export_view, "export-keys", %{"export_key_ring" => %{"code" => "#{code}"}})

      assert %{socket: %{assigns: %{export_result: :ok}}} = reload_view(%{view: export_view})

      wait_until(fn ->
        match?(%{assigns: %{me: %{name: "Exporter"}}}, reload_view(%{view: importer_view}).socket)
      end)

      render_hook(export_view, "login:export-code-close")
      assert_push_event(export_view, "chat:redirect", %{url: "/trusted"})
    end

    test "rejects a wrong code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/trusted/export-key-ring/missing")
      render_hook(view, "restoreAuth", %{"auth" => User.device_encode(User.login("X"))})

      render_hook(view, "export-keys", %{"export_key_ring" => %{"code" => "1"}})

      %{socket: %{assigns: assigns}} = reload_view(%{view: view})
      refute assigns.export_result == :ok
    end
  end

  describe "login screen navigation" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/trusted")
      render_hook(view, "restoreAuth")
      [view: view]
    end

    test "import key ring can be closed", %{view: view} do
      render_hook(view, "login:request-key-ring")
      render_hook(view, "login:import-keyring-close")

      assert %{socket: %{assigns: %{need_login: true, url: nil}}} = reload_view(%{view: view})
    end

    test "import own key ring can be reopened, cleared and closed", %{view: view} do
      render_hook(view, "login:import-own-key-ring")
      render_hook(view, "login:my-keys-file-submit")
      render_hook(view, "login:import-own-keyring-reupload")
      render_hook(view, "login:import-own-keyring:drop-password-error")
      render_hook(view, "login:import-own-keyring-close")

      assert %{socket: %{assigns: %{need_login: true}}} = reload_view(%{view: view})
    end

    test "recovery screen can be closed", %{view: view} do
      render_hook(view, "login:recover-key-share")
      assert %{socket: %{assigns: %{mode: :recover_key_share}}} = reload_view(%{view: view})

      render_hook(view, "login:recovery-key-close")
      assert %{socket: %{assigns: %{need_login: true}}} = reload_view(%{view: view})
    end
  end

  describe "live actions after login" do
    setup [:prepare_view]

    test "rooms and chats patches switch the lobby mode", %{view: view} do
      render_patch(view, "/trusted/rooms")
      assert %{socket: %{assigns: %{lobby_mode: :rooms}}} = reload_view(%{view: view})

      render_patch(view, "/trusted/chats")
      assert %{socket: %{assigns: %{lobby_mode: :chats}}} = reload_view(%{view: view})
    end

    test "push_patch message patches the view", %{view: view} do
      send(view.pid, {:push_patch, "/trusted/rooms"})
      render(view)

      assert_patch(view, "/trusted/rooms", 1_000)
    end
  end
end
