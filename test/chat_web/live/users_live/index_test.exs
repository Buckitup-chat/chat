defmodule ChatWeb.UsersLive.IndexTest do
  use ChatWeb.ConnCase
  use ChatWeb.DataCase

  import Phoenix.LiveViewTest

  alias Chat.Data.Schemas.User

  describe "UsersLive.Index" do
    test "renders users page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users")

      assert html =~ "Users Stream"
      assert html =~ "Real-time user list synced via Electric HTTP endpoint"
      assert html =~ "Using Electric.Client.stream(User)"
    end

    test "displays loading state initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/users")

      assert html =~ "Loading users from Electric..."
      assert html =~ "animate-spin"
    end

    test "loads and displays users from database", %{conn: conn} do
      # Insert test users
      Chat.Repo.insert!(%User{name: "Alice", pub_key: <<1, 2, 3>>})
      Chat.Repo.insert!(%User{name: "Bob", pub_key: <<4, 5, 6>>})

      {:ok, view, _html} = live(conn, "/users")

      # Wait for async task to complete
      :timer.sleep(100)
      html = render(view)

      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Total Users: 2"
      refute html =~ "Loading users from Electric"
    end

    test "displays empty state when no users", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/users")

      # Wait for async task
      :timer.sleep(100)
      html = render(view)

      assert html =~ "No users found"
      assert html =~ "Users will appear here when they are synced via Electric"
    end
  end
end
