defmodule ChatWeb.MainLive.Page.AdminPanelTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import ChatWeb.LiveTestHelpers.{AdminPanel, Navigation}
  import Phoenix.LiveViewTest

  alias Chat.Admin.{BackupSettings, MediaSettings}
  alias Chat.AdminRoom
  alias ChatWeb.MainLive.Admin.FirmwareUpgradeForm

  setup :reset_admin_db

  describe "backup settings form" do
    test "saves backup settings to the admin DB", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

      html = open_admin_panel(view)

      assert html =~ "Backup settings"
      assert html =~ "Should backup finish after copying data or continue syncing?"

      assert html =~
               ~S(<input checked="checked" id="backup_settings_type_regular" name="backup_settings[type]" type="radio" value="regular"/>)

      assert html =~ ~r|<span class="ml-2 text-sm font-bold">\s+Regular\s+</span>|

      assert html =~
               ~S(<input id="backup_settings_type_continuous" name="backup_settings[type]" type="radio" value="continuous"/>)

      assert html =~ ~r|<span class="ml-2 text-sm">\s+Continuous\s+</span>|

      assert html =~ ~S(phx-disable-with="Updating..." type="submit">Update</button>)

      html =
        view
        |> form("#backup_settings", %{"backup_settings" => %{"type" => "continuous"}})
        |> render_change()

      assert html =~
               ~S(<input id="backup_settings_type_regular" name="backup_settings[type]" type="radio" value="regular"/>)

      assert html =~ ~r|<span class="ml-2 text-sm">\s+Regular\s+</span>|

      assert html =~
               ~S(<input checked="checked" id="backup_settings_type_continuous" name="backup_settings[type]" type="radio" value="continuous"/>)

      assert html =~ ~r|<span class="ml-2 text-sm font-bold">\s+Continuous\s+</span>|

      assert html =~ ~S(phx-disable-with="Updating..." type="submit">Update</button>)

      view
      |> form("#backup_settings", %{"backup_settings" => %{"type" => "continuous"}})
      |> render_submit()

      assert html =~
               ~S(<input id="backup_settings_type_regular" name="backup_settings[type]" type="radio" value="regular"/>)

      assert html =~ ~r|<span class="ml-2 text-sm">\s+Regular\s+</span>|

      assert html =~
               ~S(<input checked="checked" id="backup_settings_type_continuous" name="backup_settings[type]" type="radio" value="continuous"/>)

      assert html =~ ~r|<span class="ml-2 text-sm font-bold">\s+Continuous\s+</span>|

      assert %BackupSettings{} = backup_settings = AdminRoom.get_backup_settings()
      assert backup_settings.type == :continuous
    end
  end

  describe "media settings form" do
    test "saves media settings to the admin DB", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

      html = open_admin_panel(view)

      assert html =~ "Media settings"

      assert html =~
               ~r|When new USB drive is plugged,<br/>\s+the following functionality will be started:|

      assert html =~
               ~S(<input checked="checked" id="media_settings_functionality_backup" name="media_settings[functionality]" type="radio" value="backup"/>)

      assert html =~ ~r|<span class="ml-2 text-sm font-bold">\s+Backup\s+</span>|

      assert html =~
               ~S(<input id="media_settings_functionality_onliners" name="media_settings[functionality]" type="radio" value="onliners"/>)

      assert html =~ ~r|<span class="ml-2 text-sm">\s+Onliners sync\s+</span>|

      assert html =~ ~S(phx-disable-with="Updating..." type="submit">Update</button>)

      html =
        view
        |> form("#media_settings", %{"media_settings" => %{"functionality" => "onliners"}})
        |> render_change()

      assert html =~
               ~S(<input id="media_settings_functionality_backup" name="media_settings[functionality]" type="radio" value="backup"/>)

      assert html =~ ~r|<span class="ml-2 text-sm">\s+Backup\s+</span>|

      assert html =~
               ~S(<input checked="checked" id="media_settings_functionality_onliners" name="media_settings[functionality]" type="radio" value="onliners"/>)

      assert html =~ ~r|<span class="ml-2 text-sm font-bold">\s+Onliners sync\s+</span>|

      assert html =~ ~S(phx-disable-with="Updating..." type="submit">Update</button>)

      view
      |> form("#media_settings", %{"media_settings" => %{"functionality" => "onliners"}})
      |> render_submit()

      assert html =~
               ~S(<input id="media_settings_functionality_backup" name="media_settings[functionality]" type="radio" value="backup"/>)

      assert html =~ ~r|<span class="ml-2 text-sm">\s+Backup\s+</span>|

      assert html =~
               ~S(<input checked="checked" id="media_settings_functionality_onliners" name="media_settings[functionality]" type="radio" value="onliners"/>)

      assert html =~ ~r|<span class="ml-2 text-sm font-bold">\s+Onliners sync\s+</span>|

      assert %MediaSettings{} = media_settings = AdminRoom.get_media_settings()
      assert media_settings.functionality == :onliners
    end
  end

  describe "firmware upgrade form" do
    test "saves backup settings to the admin DB", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

      open_admin_panel(view)
      assert view |> render() =~ "Firmware upgrade"
      assert view |> render() =~ "Upload"

      Phoenix.LiveView.send_update(view.pid, FirmwareUpgradeForm,
        id: :firmware_upgrade_form,
        substep: :done
      )

      assert view |> render() =~ "Upgrade"
      view |> element("button", "Upgrade") |> render_click()
      assert view |> render() =~ "Upgrade firmware?"

      assert view |> render() =~
               "Are you sure?. The reboot will be performed automatically after the upgrade."

      view |> element(".confirmButton", "Ok") |> render_click()

      assert view |> render() =~ "Upgrading..."
      assert view |> render() =~ "The reboot will be performed automatically."

      send(view.pid, {:admin, :firmware_upgraded})

      assert view |> render() =~ "Firmware upgraded"
    end
  end
end
