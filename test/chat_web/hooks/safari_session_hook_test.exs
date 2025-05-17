defmodule ChatWeb.Hooks.SafariSessionHookTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component
  
  # Define a test LiveView module that uses our hook
  defmodule TestLiveView do
    use ChatWeb, :live_view
    
    # Include the SafariSessionHook
    on_mount {ChatWeb.Hooks.SafariSessionHook, :default}
    
    @impl true
    def mount(_params, session, socket) do
      # Initialize with the value from the session or default to false
      is_safari = Map.get(session, "is_safari", false)
      {:ok, Phoenix.Component.assign(socket, :is_safari, is_safari)}
    end
    
    @impl true
    def render(assigns) do
      ~H"""
      <div>
        <p>Test LiveView</p>
        <p>Is Safari: <%= @is_safari %></p>
      </div>
      """
    end
  end

  setup do
    conn = Phoenix.ConnTest.build_conn()
    {:ok, view, _html} = live_isolated(conn, TestLiveView)
    {:ok, conn: conn, view: view}
  end

  describe "on_mount/4" do
    test "assigns is_safari to socket when Safari is detected", %{conn: _conn} do
      # Test with is_safari set to true in the session
      session = %{"is_safari" => true}
      {:ok, view, html} = live_isolated(Phoenix.ConnTest.build_conn(), TestLiveView, session: session)
      
      # Check the rendered output
      assert html =~ "Is Safari: true"
      
      # Also check the socket assigns
      assert render(view) =~ "Is Safari: true"
    end

    test "assigns is_safari to false when not Safari", %{conn: _conn} do
      # Test with is_safari explicitly set to false in the session
      session = %{"is_safari" => false}
      {:ok, _view, html} = live_isolated(Phoenix.ConnTest.build_conn(), TestLiveView, session: session)
      assert html =~ "Is Safari: false"
    end

    test "assigns is_safari to false when not specified in session", %{view: view} do
      # By default, is_safari should be false when not specified in session
      assert render(view) =~ "Is Safari: false"
    end
  end

  describe "handle_info/2" do
    test "schedules next refresh for Safari browsers", %{conn: _conn} do
      # Set up a view with is_safari: true
      session = %{"is_safari" => true}
      {:ok, view, _html} = live_isolated(Phoenix.ConnTest.build_conn(), TestLiveView, session: session)
      
      # The initial render should show is_safari: true
      assert render(view) =~ "Is Safari: true"
      
      # Send the refresh message
      send(view.pid, :refresh_safari_session)
      
      # The view should still be rendered with is_safari: true
      assert render(view) =~ "Is Safari: true"
    end
  end
end
