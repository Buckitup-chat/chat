defmodule ChatWeb.MainLive.IndexTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Identity

  describe "room sync between multiple tabs" do
    setup [:current_tab, :another_tab]

    defp current_tab(%{conn: _} = conn), do: [current_tab: login_by_key(conn)]
    defp another_tab(%{conn: _} = conn), do: [another_tab: login_by_key(conn)]

    test "on create", %{current_tab: current_tab, another_tab: another_tab} do
      %{view: current_tab_view} = current_tab
      %{view: another_tab_view} = another_tab

      %{socket: %{assigns: %{room_identity: room_identity}}} =
        create_and_open_room(%{view: current_tab_view})

      render_hook(current_tab_view, "room/sync-stored", %{
        "key" => Identity.priv_key_to_string(room_identity),
        "room_count" => 1
      })

      %{socket: %{assigns: current_view_state}} = reload_view(%{view: current_tab_view})
      %{socket: %{assigns: another_view_state}} = reload_view(%{view: another_tab_view})

      assert current_view_state.joined_rooms == another_view_state.joined_rooms
      assert current_view_state.room_count_to_backup == another_view_state.room_count_to_backup
    end
  end
end
