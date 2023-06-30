defmodule ChatWeb.MainLive.Page.AdminPanelTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Admin.{BackupSettings, CargoSettings, MediaSettings}
  alias Chat.{AdminDb, AdminRoom, Db, Identity, User}
  alias Chat.Db.ChangeTracker

  setup do
    CubDB.clear(AdminDb.db())
    CubDB.clear(Db.db())
    CubDB.set_auto_compact(AdminDb.db(), false)
  end

  describe "backup settings form" do
    test "saves backup settings to the admin DB", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

      html =
        view
        |> element(".navbar button", "Admin")
        |> render_click()

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

  describe "cargo checkpoints form" do
    test "saves checkpoints preset to the admin DB", %{conn: conn} do
      %{socket: socket, view: view} = prepare_view(%{conn: conn})

      encoded_user_pub_key =
        socket.assigns.me
        |> Identity.pub_key()
        |> Base.encode16(case: :lower)

      encoded_checkpoint_1_pub_key =
        "Checkpoint 1"
        |> User.login()
        |> tap(&User.register/1)
        |> Identity.pub_key()
        |> Base.encode16(case: :lower)

      checkpoint_2_pub_key =
        "Checkpoint 2"
        |> User.login()
        |> tap(&User.register/1)
        |> Identity.pub_key()

      ChangeTracker.await()

      encoded_checkpoint_2_pub_key = Base.encode16(checkpoint_2_pub_key, case: :lower)

      html =
        view
        |> element(".navbar button", "Admin")
        |> render_click()

      refute html =~ "Cargo checkpoints preset"

      view
      |> form("#media_settings", %{"media_settings" => %{"functionality" => "cargo"}})
      |> render_submit()

      html = render(view)

      assert html =~ "Cargo checkpoints preset"
      assert html =~ "Checkpoints are automatically invited to the Cargo rooms you create."

      assert has_element?(view, ".users-title", "Checkpoints")
      assert has_element?(view, ".users-title", "Other users")

      refute_users(view, "checkpoints", ["Checkpoint 1", "Checkpoint 2"])
      assert_users(view, "rest", ["Checkpoint 1", "Checkpoint 2"])

      view
      |> element(
        ~s(li[phx-value-type="rest"][phx-value-pub-key="#{encoded_checkpoint_1_pub_key}"])
      )
      |> render_click()

      view
      |> element(".t-buttons button", "Add")
      |> render_click()

      assert_users(view, "checkpoints", ["Checkpoint 1"])
      refute_users(view, "checkpoints", ["Checkpoint 2"])
      assert_users(view, "rest", ["Checkpoint 2"])
      refute_users(view, "rest", ["Checkpoint 1"])

      assert has_element?(
               view,
               ~s(li.selected-user[phx-value-pub-key="#{encoded_checkpoint_2_pub_key}"])
             )

      view
      |> element(
        ~s(li[phx-value-type="checkpoints"][phx-value-pub-key="#{encoded_checkpoint_1_pub_key}"])
      )
      |> render_click()

      view
      |> element("button", "Remove")
      |> render_click()

      refute_users(view, "checkpoints", ["Checkpoint 1", "Checkpoint 2"])
      assert_users(view, "rest", ["Checkpoint 1", "Checkpoint 2"])

      refute has_element?(view, "li.selected-user")

      view
      |> element("#users-rest")
      |> render_hook("move_user", %{"type" => "rest", "pub_key" => encoded_checkpoint_2_pub_key})

      assert has_element?(
               view,
               ~s(li.selected-user[phx-value-pub-key="#{encoded_user_pub_key}"])
             )

      view
      |> element("#users-rest")
      |> render_hook("move_user", %{"type" => "rest", "pub_key" => encoded_checkpoint_1_pub_key})

      assert has_element?(
               view,
               ~s(li.selected-user[phx-value-pub-key="#{encoded_user_pub_key}"])
             )

      view
      |> element("#users-checkpoints")
      |> render_hook("move_user", %{
        "type" => "checkpoints",
        "pub_key" => encoded_checkpoint_1_pub_key
      })

      assert_users(view, "checkpoints", ["Checkpoint 2"])
      refute_users(view, "checkpoints", ["Checkpoint 1"])
      assert_users(view, "rest", ["Checkpoint 1"])
      refute_users(view, "rest", ["Checkpoint 2"])

      assert has_element?(
               view,
               ~s(li.selected-user[phx-value-pub-key="#{encoded_checkpoint_2_pub_key}"])
             )

      assert %CargoSettings{} = cargo_settings = AdminRoom.get_cargo_settings()
      assert cargo_settings.checkpoints == [checkpoint_2_pub_key]
    end

    defp assert_users(view, type, users) do
      Enum.each(users, fn user ->
        assert view
               |> element(~s(.users-list li[phx-value-type="#{type}"] p), user)
               |> has_element?(),
               "Expected to have #{user} in #{humanized_type(type)}"
      end)
    end

    defp refute_users(view, type, users) do
      Enum.each(users, fn user ->
        refute view
               |> element(~s(.users-list li[phx-value-type="#{type}"] p), user)
               |> has_element?(),
               "Expected not to have #{user} in #{humanized_type(type)}"
      end)
    end

    defp humanized_type("checkpoints"), do: "Checkpoints"
    defp humanized_type("rest"), do: "Other users"
  end

  describe "cargo camera sensors form" do
    test "validates camera urls", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

      view
      |> element(".navbar button", "Admin")
      |> render_click()

      refute view |> render() =~ "Cargo camera sensors"

      view
      |> form("#media_settings", %{"media_settings" => %{"functionality" => "cargo"}})
      |> render_submit()

      refute view |> render() =~ "Cargo camera sensors"

      view
      |> form("#cargo_user_form", %{"user" => %{"name" => "CargoBot"}})
      |> render_submit()

      assert view |> render() =~ "Cargo camera sensors"

      view
      |> element(".camera-sensor-input-form")
      |> render_change(%{"_target" => ["0"], "0" => "hello"})

      assert view |> render() =~ "Please remove invalid sensors."

      view |> element(".camera-sensor-input-form .camera-sensor button") |> render_click()

      refute view |> render() =~ "Please remove invalid sensors."
    end
  end

  describe "media settings form" do
    test "saves media settings to the admin DB", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

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
