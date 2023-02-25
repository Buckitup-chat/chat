defmodule ChatWeb.Helpers.OnlinersSyncTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

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
      assert MapSet.size(keys) == 3
    end

    test "doesn't crash when user is not logged in", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      state = :sys.get_state(view.pid)

      PubSub.subscribe(Chat.PubSub, "chat_onliners->platform_onliners")

      OnlinersSync.get_user_keys(state.socket)

      refute_receive {:user_keys, _keys}
    end
  end

  test "doesn't crash when user has logged out recently", %{conn: conn} do
    %{view: view} = prepare_view(%{conn: conn})

    view
    |> element(~S{[phx-click="logout-wipe"]})
    |> render_click()

    state = :sys.get_state(view.pid)

    OnlinersSync.get_user_keys(state.socket)

    refute_receive {:user_keys, _keys}
  end
end
