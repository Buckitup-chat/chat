defmodule ChatWeb.ElectricLive.IndexTest do
  use ChatWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "ElectricLive.Index" do
    test "renders electric index page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric")

      assert html =~ "Electric-Synced LiveViews"
      assert html =~ "Real-time, read-only views powered by Electric sync"
    end

    test "displays user cards link", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric")

      assert html =~ "User Cards"
      assert html =~ "Post-Quantum Users"
      assert html =~ "/electric/v1/user_card"
    end

    test "shows information about Electric sync", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric")

      assert html =~ "About Electric Sync"
      assert html =~ "read-only"
      assert html =~ "real-time"
    end

    test "user cards link navigates to correct page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/electric")

      assert view
             |> element("a[href='/electric/user_cards']")
             |> render() =~ "User Cards"
    end
  end
end
