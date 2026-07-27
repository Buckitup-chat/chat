defmodule ChatWeb.ElectricLive.ModerationSandboxLiveTest do
  @moduledoc "Page wiring for the origin moderation sandbox."
  use ChatWeb.ConnCase, async: true, group: :electric_liveview
  use ChatWeb.DataCase

  import Phoenix.LiveViewTest

  describe "ElectricLive.ModerationSandboxLive.Index" do
    test "renders the identity import step", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/moderation_sandbox")

      assert html =~ "Origin Moderation Sandbox"
      assert html =~ "Step 1: Import Origin Identity"
      assert html =~ "Import Identity"
    end

    test "hides the moderation queue until an identity is verified", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/moderation_sandbox")

      refute html =~ "Step 2: Moderation Queue"
      assert html =~ "Request Log"
      assert html =~ "No requests yet"
    end

    test "links to the origin owner sandbox as the identity source", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/moderation_sandbox")

      assert html =~ "/electric/origin_sandbox"
    end
  end
end
