defmodule ChatWeb.ElectricLive.ReviewSandboxLiveTest do
  @moduledoc "Page wiring for the review author sandbox."
  use ChatWeb.ConnCase, async: true, group: :electric_liveview
  use ChatWeb.DataCase

  import Phoenix.LiveViewTest

  describe "ElectricLive.ReviewSandboxLive.Index" do
    test "renders the identity import step", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/review_sandbox")

      assert html =~ "Review Author Sandbox"
      assert html =~ "Step 1: Import Author Identity"
      assert html =~ "Import Keys"
    end

    test "hides the later steps until an identity is imported", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/review_sandbox")

      refute html =~ "Step 2: Submit Review"
      refute html =~ "Step 3: Submit Rights"
      refute html =~ "Step 5: Add to Review List"
    end

    test "still renders the request log after it moved to ElectricLive.RequestLog", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/review_sandbox")

      assert html =~ "Request Log"
      assert html =~ "No requests yet"
    end

    test "step 5 is implemented", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/review_sandbox")

      refute html =~ "Not implemented yet"
    end

    test "links to the user sandbox as the identity source", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/review_sandbox")

      assert html =~ "/electric/user_sandbox"
    end
  end

  describe "ElectricLive.ModerationSandboxLive.Index shares the request log" do
    test "renders it from its new home", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/moderation_sandbox")

      assert html =~ "Request Log"
      assert html =~ "No requests yet"
    end
  end
end
