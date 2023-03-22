defmodule ChatWeb.OnlinersPresenceTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias ChatWeb.Presence

  test "gathers users' keys", %{conn: conn} do
    %{view: view} = prepare_view(%{conn: conn})
    open_dialog(%{view: view})
    create_and_open_room(%{view: view})

    %{view: view} = prepare_view(%{conn: conn})
    open_dialog(%{view: view})
    create_and_open_room(%{view: view})
    create_and_open_room(%{view: view})

    assert [
             {_user_hash, %{metas: [%{keys: keys_1}]}},
             {_user_2_hash, %{metas: [%{keys: keys_2}]}}
           ] = Presence.list("onliners_sync") |> Map.to_list()

    all_keys = MapSet.union(keys_1, keys_2)
    assert MapSet.size(all_keys) == 5
  end

  test "doesn't list users that are not logged in", %{conn: conn} do
    {:ok, _view, _html} = live(conn, "/")

    assert Presence.list("onliners_sync") |> Enum.empty?()
  end

  test "doesn't crash user's keys when they have logged out recently", %{conn: conn} do
    %{view: view} = prepare_view(%{conn: conn})

    view
    |> element(~S{[phx-click="logout-wipe"]})
    |> render_click()

    assert Presence.list("onliners_sync") |> Enum.empty?()
  end
end
