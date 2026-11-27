defmodule ChatWeb.MainLive.Page.LobbyTest do
  use ChatWeb.ConnCase, async: true, group: :cubdb

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest
  import Support.RetryHelper

  alias Chat.Card
  alias Chat.Db.StatusPoller
  alias Chat.Identity

  @wait 3_000

  describe "user search" do
    setup [:prepare_view]

    test "filters users and ignores list updates until reset", %{conn: conn, view: view} do
      name = unique_name("Zeb")
      other_key = %{conn: conn} |> prepare_view(name) |> my_key()
      my_id = assigns(view).my_id

      retry_until(@wait, fn ->
        render_hook(view, "lobby/search", %{"dialog" => %{"name" => " #{name} "}})
        assert %{search_filter: :on, users: [%{pub_key: ^other_key}]} = assigns(view)
      end)

      send(view.pid, {:new_user, Card.from_identity(Identity.create("Late"))})
      send(view.pid, {:lobby, :refresh_rooms_and_users})

      assert %{users: [%{pub_key: ^other_key}]} = assigns(view)

      render_hook(view, "lobby/search", %{"_target" => ["reset"], "dialog" => %{"name" => ""}})

      assert %{search_filter: :off, users: [%{pub_key: ^my_id} | _]} = assigns(view)
    end
  end

  describe "room search" do
    setup [:prepare_view]

    test "filters rooms and ignores new rooms until reset", %{conn: conn, view: view} do
      %{socket: %{assigns: %{room: %{name: name, pub_key: room_key}}}} =
        %{conn: conn} |> prepare_view("Room owner") |> create_and_open_room()

      retry_until(@wait, fn ->
        render_hook(view, "lobby/search", %{"room" => %{"name" => name}})
        assert %{search_filter: :on, new_rooms: [%{pub_key: ^room_key}]} = assigns(view)
      end)

      send(view.pid, {:new_room, %{}})

      assert %{new_rooms: [%{pub_key: ^room_key}]} = assigns(view)

      render_hook(view, "lobby/search", %{"_target" => ["reset"], "room" => %{"name" => ""}})

      assert %{search_filter: :off} = assigns(view)
    end
  end

  describe "room requests" do
    setup %{conn: conn} do
      %{view: owner_view, socket: %{assigns: %{room: room}}} =
        %{conn: conn} |> prepare_view("Owner") |> create_and_open_room()

      %{view: requester_view} = requester = prepare_view(%{conn: conn}, "Requester")

      %{owner_view: owner_view, room: room, requester_view: requester_view, requester: requester}
    end

    test "request approved by room hash lets the requester join", %{
      owner_view: owner_view,
      room: %{pub_key: room_key},
      requester_view: requester_view,
      requester: requester
    } do
      render_hook(requester_view, "room/send-request", %{"room" => hex(room_key)})
      send(owner_view.pid, {:room_request, hex(room_key), my_key(requester)})

      retry_until(@wait, fn -> assert Map.has_key?(assigns(requester_view).room_map, room_key) end)
    end

    test "approval of a joined room or for another user is ignored", %{
      owner_view: owner_view,
      room: %{pub_key: room_key},
      requester: requester
    } do
      %{my_id: my_id, room_map: room_map} = assigns(owner_view)

      send(owner_view.pid, {:room_request_approved, "not ciphered", my_id, room_key})
      send(owner_view.pid, {:room_request_approved, "not ciphered", my_key(requester), "other"})

      assert %{room_map: ^room_map} = assigns(owner_view)
    end

    test "malformed room hash in a request is ignored", %{
      owner_view: owner_view,
      room: %{pub_key: room_key},
      requester: requester
    } do
      send(owner_view.pid, {:room_request, "not hex", my_key(requester)})

      assert %{room: %{pub_key: ^room_key}} = assigns(owner_view)
    end
  end

  describe "status" do
    setup [:prepare_view]

    test "db status update is assigned", %{view: view} do
      status = Map.put(StatusPoller.info(), :compacting, :test_marker)

      send(view.pid, {:db_status, status})

      assert %{db_status: %{compacting: :test_marker}} = assigns(view)
    end
  end

  # Helpers

  defp assigns(view), do: reload_view(%{view: view}).socket.assigns

  defp hex(key), do: Base.encode16(key, case: :lower)

  defp my_key(%{socket: %{assigns: %{me: me}}}), do: Identity.pub_key(me)

  defp unique_name(prefix), do: "#{prefix}#{System.unique_integer([:positive])}"
end
