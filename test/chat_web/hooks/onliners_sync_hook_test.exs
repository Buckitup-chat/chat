defmodule ChatWeb.Hooks.OnlinersSyncHookTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers

  alias Phoenix.PubSub

  describe "on_mount/4" do
    test "handles get_user_keys messages", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})
      open_dialog(%{view: view})

      PubSub.broadcast(Chat.PubSub, "platform_onliners->chat_onliners", "get_user_keys")
      :timer.sleep(100)
    end
  end
end
