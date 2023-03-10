defmodule ChatWeb.MainLive.Page.AdminPanelTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Admin.MediaSettings
  alias Chat.{AdminDb, AdminRoom}
  alias Phoenix.PubSub

  setup do
    AdminDb.db()
    |> CubDB.clear()
  end

  describe "media settings form" do
    test "saves media settings to the admin DB", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})
      PubSub.subscribe(Chat.PubSub, "chat->platform")

      html =
        view
        |> element(".navbar button", "Admin")
        |> render_click()

      assert html =~ "Media settings"

      assert html =~
               ~r|When new USB drive is plugged into the secondary port,<br/>\s+the following functionality will be started:|

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
end
