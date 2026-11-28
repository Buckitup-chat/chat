defmodule ChatWeb.MainLive.Page.AdminPanelCargoCheckpointsTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import ChatWeb.LiveTestHelpers.{AdminPanel, Navigation}
  import Phoenix.LiveViewTest

  alias Chat.Admin.CargoSettings
  alias Chat.{AdminRoom, Identity, User}
  alias Chat.Db.ChangeTracker
  alias Chat.User.UsersBroker

  setup :reset_admin_db

  describe "cargo checkpoints form" do
    @tag :skip
    # todo: explain
    # todo: migrate from dropdowns to select and button click
    test "saves checkpoints preset to the admin DB", %{conn: conn} do
      %{socket: socket, view: view} = prepare_view(%{conn: conn})

      encoded_user_pub_key =
        socket.assigns.me
        |> Identity.pub_key()
        |> Base.encode16(case: :lower)

      {encoded_checkpoint_1_pub_key, _card1} =
        "Checkpoint 1"
        |> User.login()
        |> tap(&User.register/1)
        |> tap(&UsersBroker.put/1)
        |> then(fn identity ->
          {
            identity |> Identity.pub_key() |> Base.encode16(case: :lower),
            identity |> Chat.Card.from_identity()
          }
        end)

      {checkpoint_2_pub_key, card2} =
        "Checkpoint 2"
        |> User.login()
        |> tap(&User.register/1)
        |> tap(&UsersBroker.put/1)
        |> then(fn identity ->
          {
            identity |> Identity.pub_key(),
            identity |> Chat.Card.from_identity()
          }
        end)

      ChangeTracker.await()

      encoded_checkpoint_2_pub_key = Base.encode16(checkpoint_2_pub_key, case: :lower)

      html = open_admin_panel(view)

      refute html =~ "Cargo checkpoints preset"

      view
      |> form("#media_settings", %{"media_settings" => %{"functionality" => "cargo"}})
      |> render_submit()

      html = render(view)

      assert html =~ "Cargo checkpoints preset"
      assert html =~ "Checkpoints are automatically invited to the Cargo rooms you create."

      assert has_element?(view, ".users-title", "Checkpoints")
      assert has_element?(view, ".users-title", "Other users")

      assert listed_users(view, "checkpoints", ["Checkpoint 1", "Checkpoint 2"]) == []

      assert listed_users(view, "rest", ["Checkpoint 1", "Checkpoint 2"]) == [
               "Checkpoint 1",
               "Checkpoint 2"
             ]

      view
      |> element(
        ~s(li[phx-value-type="rest"][phx-value-pub-key="#{encoded_checkpoint_1_pub_key}"])
      )
      |> render_click()

      view
      |> element(".t-buttons button", "Add")
      |> render_click()

      assert listed_users(view, "checkpoints", ["Checkpoint 1"]) == ["Checkpoint 1"]
      assert listed_users(view, "checkpoints", ["Checkpoint 2"]) == []
      assert listed_users(view, "rest", ["Checkpoint 2"]) == ["Checkpoint 2"]
      assert listed_users(view, "rest", ["Checkpoint 1"]) == []

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

      assert listed_users(view, "checkpoints", ["Checkpoint 1", "Checkpoint 2"]) == []

      assert listed_users(view, "rest", ["Checkpoint 1", "Checkpoint 2"]) == [
               "Checkpoint 1",
               "Checkpoint 2"
             ]

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

      assert listed_users(view, "checkpoints", ["Checkpoint 2"]) == ["Checkpoint 2"]
      assert listed_users(view, "checkpoints", ["Checkpoint 1"]) == []
      assert listed_users(view, "rest", ["Checkpoint 1"]) == ["Checkpoint 1"]
      assert listed_users(view, "rest", ["Checkpoint 2"]) == []

      assert has_element?(
               view,
               ~s(li.selected-user[phx-value-pub-key="#{encoded_checkpoint_2_pub_key}"])
             )

      assert %CargoSettings{} = cargo_settings = AdminRoom.get_cargo_settings()
      assert cargo_settings.checkpoints == [card2]
    end

    defp listed_users(view, type, users) do
      Enum.filter(users, fn user ->
        view
        |> element(~s(.users-list li[phx-value-type="#{type}"]), user)
        |> has_element?()
      end)
    end
  end
end
