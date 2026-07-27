defmodule ChatWeb.ElectricLive.IndexTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  use Rewire

  defmodule ReadinessMock do
    def check_readiness, do: :ready
  end

  rewire(ChatWeb.ElectricLive.Index, ElectricReadiness: ReadinessMock, as: ReadyIndex)

  describe "ElectricLive.Index" do
    test "renders electric index page", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, ReadyIndex)

      assert html =~ "Electric-Synced LiveViews"
      assert html =~ "Real-time, read-only views powered by Electric sync"
    end

    test "displays user cards link", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, ReadyIndex)

      assert html =~ "User Cards"
      assert html =~ "/electric/user_cards"
    end

    test "shows information about Electric sync", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, ReadyIndex)

      assert html =~ "About Electric Sync"
      assert html =~ "read-only"
      assert html =~ "real-time"
    end

    test "lists the moderation sandbox", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, ReadyIndex)

      assert html =~ "Moderation Sandbox"
      assert html =~ "/electric/moderation_sandbox"
    end

    test "user cards link navigates to correct page", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, ReadyIndex)

      assert view
             |> element("a[href='/electric/user_cards']")
             |> render() =~ "User Cards"
    end
  end
end
