defmodule ChatWeb.MainLive.Page.AdminPanelRouterInfoTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.{AdminDb, AdminRoom, Db, User}
  alias Chat.User.UsersBroker
  alias Phoenix.PubSub

  @to_platform "chat->platform"

  setup do
    CubDB.clear(AdminDb.db())
    CubDB.clear(Db.db())
    UsersBroker.sync()
    PubSub.subscribe(Chat.PubSub, @to_platform)
  end

  describe "wifi" do
    test "shows platform wifi settings, then confirms an update", %{conn: conn} do
      view = open_admin(conn)

      platform_says(view, {:wifi_settings, %{ssid: "office", password: "from-platform"}})

      assert %{wifi_ssid: "office", wifi_password: "from-platform", wifi_loaded: true} =
               assigns(view)

      render_hook(view, "admin/wifi-submit", %{"ssid" => "office", "password" => "stored"})
      platform_says(view, {:updated_wifi_settings, :ok})
      assert %{wifi_loaded: true} = assigns(view)

      platform_says(view, {:wifi_settings, %{ssid: "office", password: "from-platform"}})
      assert %{wifi_password: "stored"} = assigns(view)
    end
  end

  describe "device state" do
    test "renders lan settings sent by platform", %{conn: conn} do
      view = open_admin(conn)

      platform_says(view, {:lan_ip, "10.0.0.7"})
      platform_says(view, {:lan_profile, :dhcp})
      platform_says(view, {:lan_known_profiles, [:dhcp, :static]})
      platform_says(view, {:updated_lan_profile, :ok})

      html = render(view)
      assert html =~ "10.0.0.7"
      assert html =~ ~S(<option selected="selected" value="dhcp">Dhcp</option>)
    end

    test "device log redirects to a temp download", %{conn: conn} do
      view = open_admin(conn)
      entry = {:info, {Logger, "booted", {{2026, 11, 27}, {10, 0, 0, 5}}, %{}}}

      platform_says(view, {:device_log, {nil, [entry]}})

      assert_push_event(view, "chat:redirect", %{url: url})
      assert url =~ "device_log"
    end

    test "gpio24 impedance status renders On and Off", %{conn: conn} do
      view = open_admin(conn)

      platform_says(view, {:gpio24_impedance_status, 1})
      assert %{gpio24_impedance_status: "On"} = assigns(view)

      platform_says(view, {:gpio24_impedance_status, 0})
      assert %{gpio24_impedance_status: "Off"} = assigns(view)
    end

    test "internal db outage shows a flash; errors and unmount are ignored", %{conn: conn} do
      view = open_admin(conn)

      platform_says(view, {:error, :whatever})
      platform_says(view, {:unmounted_main, :ok})
      platform_says(view, {:internal_db_unavailable, %{cubdb: true, pg: false}})

      assert %{flash: %{"error" => error}} = assigns(view)
      assert error =~ "Internal database did not start (CubDB ready, PostgreSQL down)."
    end
  end

  describe "cargo weight sensor" do
    test "forwards a connection request and renders its outcome", %{conn: conn} do
      AdminRoom.store_cargo_user(User.login("Cargo"))
      view = open_admin(conn)

      send(view.pid, {:admin, {:connect_to_weight_sensor, {"NCI", "/dev/ttyUSB0"}, []}})
      assert_receive {:connect_to_weight_sensor, {"NCI", "/dev/ttyUSB0"}, []}

      platform_says(view, {:weight_sensor_connection, {:ok, "12.5 kg"}})
      assert render(view) =~ "12.5 kg"
      assert render(view) =~ "Established"

      platform_says(view, {:weight_sensor_connection, {:error, :timeout}})
      assert render(view) =~ "Failed"
    end
  end

  describe "component updates" do
    test "refresh, network status and github upgrade responses keep the panel alive", %{
      conn: conn
    } do
      view = open_admin(conn)

      send(view.pid, {:admin, :refresh_rooms_and_users})
      send(view.pid, {:admin, {:network_source_status, 1, :active}})
      send(view.pid, {:admin, {:electric_sync_status, "http://peer", :users, :live}})
      platform_says(view, {:github_firmware_upgrade, {:download_progress, 42}})

      assert render(view) =~ "Admin List"
      assert Process.alive?(view.pid)
    end
  end

  # Helpers

  defp open_admin(conn) do
    %{view: view} = prepare_view(%{conn: conn})
    view |> element(".navbar button", "Admin") |> render_click()
    view
  end

  defp platform_says(view, message) do
    send(view.pid, {:platform_response, message})
    render(view)
  end

  defp assigns(view), do: reload_view(%{view: view}).socket.assigns
end
