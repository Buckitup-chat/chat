defmodule ChatWeb.MainLive.Page.AdminPanelTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Admin.{CargoSettings, MediaSettings}
  alias Chat.{AdminDb, AdminRoom, Db, Identity, User}
  alias Chat.Db.ChangeTracker
  alias Phoenix.PubSub

  setup do
    CubDB.clear(AdminDb.db())
    CubDB.clear(Db.db())
  end

  describe "cargo settings form" do
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
      |> element("button", "Add")
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
