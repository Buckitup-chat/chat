defmodule ChatWeb.Hooks.OnlinersSyncHookTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers

  alias Phoenix.Socket.Broadcast

  describe "on_mount/4" do
    test "handles get_user_keys messages", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})
      open_dialog(%{view: view})

      assert %Broadcast{} = send(view.pid, %Broadcast{event: "get_user_keys"})
      :timer.sleep(100)
    end
  end
end
