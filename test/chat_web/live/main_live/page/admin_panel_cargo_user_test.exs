defmodule ChatWeb.MainLive.Page.AdminPanelCargoUserTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import ChatWeb.LiveTestHelpers.{AdminPanel, Navigation}
  import Phoenix.LiveViewTest

  alias Chat.{AdminRoom, Card, Dialogs, Identity}
  alias Chat.Db.ChangeTracker

  setup :reset_admin_db

  describe "cargo user form" do
    test "create a cargo user", %{conn: conn} do
      %{view: view, socket: %{assigns: %{me: admin}}} = prepare_view(%{conn: conn})

      open_admin_panel(view)

      assert view |> render() =~ "Cargo user"

      view
      |> form("#cargo_user_form", %{"user" => %{"name" => "CargoBot888"}})
      |> render_submit()

      assert view |> render() =~ "CargoBot888"
      assert view |> render() =~ "Download the Keys"

      # the backup text and file messages are written by a background task
      assert :ok = wait_until(fn -> backup_file_sent?(admin) end, "backup file", timeout: 5_000)
      ChangeTracker.await()

      view
      |> element(".navbar button", "Chats")
      |> render_click()

      %{socket: socket} = reload_view(%{view: view})

      cargo_bot_hash =
        socket.assigns.users |> Enum.find(&(&1.name == "CargoBot888")) |> Map.get(:hash)

      view
      |> element("#user-#{cargo_bot_hash}")
      |> render_click()

      assert has_vue_content?(
               view |> render(),
               "LinkedText",
               "The backup `CargoBot888.data` is not encrypted. Do not share it with anyone."
             )

      assert view |> render() =~ "CargoBot888.data"
    end

    test "upload a cargo user", %{conn: conn} do
      %{view: view, socket: %{assigns: %{me: admin}}} = prepare_view(%{conn: conn})

      open_admin_panel(view)

      assert view |> render() =~ "Cargo user"

      content = File.read!("test/support/fixtures/import_keys/TestUser.data")

      [identity_strings | _] = Jason.decode!(content)
      test_user = Chat.Identity.from_strings(identity_strings)
      test_user_hash = test_user.public_key |> Base.encode16(case: :lower)

      cargo_user =
        file_input(view, "#upload-cargo-user", :config, [
          %{
            last_modified: 1_594_171_879_000,
            name: "TestUser.data",
            content: content,
            size: byte_size(content),
            type: "text/plain"
          }
        ])

      render_upload(cargo_user, "TestUser.data", 100)

      assert view |> render() =~ "Test User"
      assert view |> render() =~ "Download the Keys"

      # the backup text and file messages are written by a background task
      assert :ok = wait_until(fn -> backup_file_sent?(admin) end, "backup file", timeout: 5_000)
      ChangeTracker.await()

      view
      |> element(".navbar button", "Chats")
      |> render_click()

      view
      |> element("#user-#{test_user_hash}")
      |> render_click()

      assert has_vue_content?(
               view |> render(),
               "LinkedText",
               "The backup `TestUser.data` is not encrypted. Do not share it with anyone."
             )

      assert view |> render() =~ "TestUser.data"
    end
  end

  describe "cargo camera sensors form" do
    test "validates camera urls", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})

      open_admin_panel(view)

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

  defp backup_file_sent?(admin) do
    case AdminRoom.get_cargo_user() do
      %Identity{} = cargo_user ->
        cargo_user
        |> Dialogs.open(Card.from_identity(admin))
        |> Dialogs.read(admin)
        |> Enum.any?(&(&1.type == :file))

      _ ->
        false
    end
  end
end
