defmodule ChatWeb.ElectricLive.UserSandboxLiveTest do
  @moduledoc """
  Tests for Electric API Sandbox LiveView.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Phoenix.LiveViewTest

  describe "ElectricLive.UserSandboxLive.Index" do
    test "renders sandbox page with initial state", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      assert html =~ "Electric API Sandbox"
      assert html =~ "No user loaded"
      assert html =~ "Create Test User"
    end

    test "displays left sidebar with documentation", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      assert html =~ "Documentation"
      assert html =~ "User Card"
      assert html =~ "User Storage"
    end

    test "displays empty request log initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      assert html =~ "Request Log"
      assert html =~ "No requests yet"
    end

    test "can toggle documentation sidebar", %{conn: conn} do
      {:ok, view, html} = live(conn, "/electric/user_sandbox")

      # Initially shown - check for doc content
      assert html =~ "User Card"
      assert html =~ "SHA3-512 hash"

      # Toggle to hide
      html = view |> element("button", "◄") |> render_click()
      # When hidden, we should see the "Show docs" title on the button
      assert html =~ "title=\"Show docs\""
      refute html =~ "SHA3-512 hash"

      # Toggle to show
      html = view |> element("button", "►") |> render_click()
      assert html =~ "title=\"Hide docs\""
      assert html =~ "SHA3-512 hash"
    end

    test "can expand/collapse doc sections", %{conn: conn} do
      {:ok, view, html} = live(conn, "/electric/user_sandbox")

      # user_card is expanded by default
      assert html =~ "SHA3-512 hash of sign_pkey"

      # Collapse user_card
      view |> element("button", "User Card") |> render_click()
      html = render(view)
      refute html =~ "SHA3-512 hash of sign_pkey"

      # Expand user_storage
      view |> element("button", "User Storage") |> render_click()
      html = render(view)
      assert html =~ "max 10MB per entry"
    end

    test "displays correct initial form elements", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      assert html =~ "name=\"name\""
      assert html =~ "Enter user name"
      assert html =~ "phx-submit=\"create_user\""
    end

    test "has clear log button (disabled when empty)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      # No Clear button when log is empty
      refute html =~ ">Clear</button>"

      # If we had requests, we'd see the Clear button
      # (This would require actual API integration or mocking)
    end

    test "sidebar toggle button has correct title attributes", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      assert html =~ "title=\"Hide docs\""
    end

    test "initial state shows correct UI elements", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_sandbox")

      # Verify initial state through UI
      assert html =~ "No user loaded"
      assert html =~ "Create Test User"
      assert html =~ "No requests yet"
      assert html =~ "title=\"Hide docs\""

      # User card section should be expanded by default
      assert html =~ "SHA3-512 hash"

      # No error message
      refute html =~ "bg-red-50"
    end
  end
end
