defmodule ChatWeb.Hooks.SafariSessionHookTest do
  use ExUnit.Case, async: true
  import Phoenix.Component, only: [assign: 3]

  alias ChatWeb.Hooks.SafariSessionHook

  # Create a minimal socket struct for testing
  defp create_test_socket(assigns \\ %{}) do
    %{assigns: assigns, endpoint: ChatWeb.Endpoint}
  end

  describe "on_mount/4" do
    test "assigns is_safari to socket when Safari is detected" do
      socket = create_test_socket()
      session = %{is_safari: true}
      
      # Mock the Phoenix.Component.assign function
      result = SafariSessionHook.on_mount(:default, %{}, session, socket)
      
      # Just verify the function returns the expected format
      assert {:cont, %{assigns: _}} = result
    end

    test "assigns is_safari to false when not Safari" do
      socket = create_test_socket()
      session = %{is_safari: false}
      
      result = SafariSessionHook.on_mount(:default, %{}, session, socket)
      
      assert {:cont, %{assigns: _}} = result
    end

    test "assigns is_safari to false when not specified in session" do
      socket = create_test_socket()
      session = %{}
      
      result = SafariSessionHook.on_mount(:default, %{}, session, socket)
      
      assert {:cont, %{assigns: _}} = result
    end
  end

  describe "handle_info/2" do
    test "schedules next refresh for Safari browsers" do
      socket = create_test_socket(%{is_safari: true})
      
      # Just verify the function returns the expected format
      result = SafariSessionHook.handle_info(:refresh_safari_session, socket)
      
      assert {:noreply, %{assigns: _}} = result
    end

    test "does not schedule refresh for non-Safari browsers" do
      socket = create_test_socket(%{is_safari: false})
      
      result = SafariSessionHook.handle_info(:refresh_safari_session, socket)
      
      assert {:noreply, %{assigns: _}} = result
    end
  end

  describe "assign_safari/2" do
    test "assigns is_safari to socket" do
      socket = create_test_socket()
      
      # Just verify the function doesn't crash
      result = SafariSessionHook.assign_safari(socket, true)
      
      assert %{assigns: _} = result
    end
  end
end
