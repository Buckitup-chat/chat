defmodule ChatWeb.Helpers.OnlinersSyncTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest
  import Support.{FakeData, RetryHelper}

  alias ChatWeb.Helpers.OnlinersSync
  alias Phoenix.PubSub

  describe "get_user_keys/1" do
    test "gathers current user's keys", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})
      open_dialog(%{view: view})
      create_and_open_room(%{view: view})

      %{view: view} = prepare_view(%{conn: conn})
      open_dialog(%{view: view})
      create_and_open_room(%{view: view})
      %{socket: socket} = create_and_open_room(%{view: view})

      PubSub.subscribe(Chat.PubSub, "chat_onliners->platform_onliners")

      OnlinersSync.get_user_keys(socket)

      assert_receive {:user_keys, keys}
      assert length(keys) == 3
    end
  end
end
