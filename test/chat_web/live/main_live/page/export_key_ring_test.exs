defmodule ChatWeb.MainLive.Page.ExportKeyRingTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Rewire

  alias Chat.Identity
  alias ChatWeb.MainLive.Page.ExportKeyRing

  # Define mock module for KeyRingTokens
  defmodule KeyRingTokensMock do
    def get(uuid, code) do
      # This will be dynamically set in the test
      case Process.get({:key_ring_tokens_get, uuid, code}) do
        nil -> :error
        result -> result
      end
    end
  end

  describe "ExportKeyRing component" do
    setup [:prepare_view, :setup_export_data]

    test "init assigns proper values", %{view: view, test_uuid: test_uuid} do
      # Call the init function
      socket = view.pid |> :sys.get_state() |> Map.get(:socket)

      updated_socket = ExportKeyRing.init(socket, test_uuid)

      # Verify the socket assigns
      assert updated_socket.assigns.mode == :export_key_ring
      assert updated_socket.assigns.export_id == test_uuid
      assert updated_socket.assigns.export_result == false
    end

    test "send_key_ring with valid code sets export_result to :ok",
         %{view: view, test_uuid: test_uuid, test_code: test_code, mock_pid: mock_pid} do
      # Set up the mock to return success
      Process.put({:key_ring_tokens_get, test_uuid, test_code}, {:ok, mock_pid})

      # Rewire the component with mocked dependencies
      rewired_export_key_ring =
        rewire(ExportKeyRing, [
          {Chat.KeyRingTokens, KeyRingTokensMock}
        ])

      socket = view.pid |> :sys.get_state() |> Map.get(:socket)

      # Initialize the socket first
      socket = rewired_export_key_ring.init(socket, test_uuid)

      # Add required assigns that would normally be set by the LiveView
      socket = %{
        socket
        | assigns:
            Map.merge(socket.assigns, %{
              me: Identity.create("Test User"),
              rooms: %{},
              monotonic_offset: 0
            })
      }

      # Call send_key_ring with the valid code
      updated_socket = rewired_export_key_ring.send_key_ring(socket, test_code)

      # Verify the result
      assert updated_socket.assigns.export_result == :ok
    end

    test "send_key_ring with invalid code sets export_result to :error",
         %{view: view, test_uuid: test_uuid, test_code: test_code} do
      # Set up the mock to return error
      Process.put({:key_ring_tokens_get, test_uuid, test_code}, :error)

      # Rewire the component with mocked dependencies
      rewired_export_key_ring =
        rewire(ExportKeyRing, [
          {Chat.KeyRingTokens, KeyRingTokensMock}
        ])

      socket = view.pid |> :sys.get_state() |> Map.get(:socket)

      # Initialize the socket first
      socket = rewired_export_key_ring.init(socket, test_uuid)

      # Add required assigns that would normally be set by the LiveView
      socket = %{
        socket
        | assigns:
            Map.merge(socket.assigns, %{
              me: Identity.create("Test User"),
              rooms: %{},
              monotonic_offset: 0
            })
      }

      # Call send_key_ring with the invalid code
      updated_socket = rewired_export_key_ring.send_key_ring(socket, test_code)

      # Verify the result
      assert updated_socket.assigns.export_result == :error
    end

    test "error sets export_result to :error", %{view: view, test_uuid: test_uuid} do
      socket = view.pid |> :sys.get_state() |> Map.get(:socket)

      # Initialize the socket first
      socket = ExportKeyRing.init(socket, test_uuid)

      # Call error
      updated_socket = ExportKeyRing.error(socket)

      # Verify the result
      assert updated_socket.assigns.export_result == :error
    end

    test "close resets export_id and export_result", %{view: view, test_uuid: test_uuid} do
      socket = view.pid |> :sys.get_state() |> Map.get(:socket)

      # Initialize the socket first
      socket = ExportKeyRing.init(socket, test_uuid)

      # Call close
      updated_socket = ExportKeyRing.close(socket)

      # Verify the result
      assert updated_socket.assigns.export_id == nil
      assert updated_socket.assigns.export_result == nil
    end
  end

  # Helper functions
  defp setup_export_data(%{conn: _conn}) do
    test_uuid = "test-uuid-123"
    test_code = "123456"

    mock_pid =
      spawn(fn ->
        receive do
          _ -> :ok
        end
      end)

    [test_uuid: test_uuid, test_code: test_code, mock_pid: mock_pid]
  end
end
