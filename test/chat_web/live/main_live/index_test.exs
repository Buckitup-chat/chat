defmodule ChatWeb.MainLive.IndexTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Dialogs
  alias Chat.Dialogs.PrivateMessage
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

  describe "downloading messages" do
    setup [:prepare_view, :open_dialog]

    test "multiple at once", %{conn: conn, view: view} do
      %{file: file, filename: filename, socket: socket} = start_upload(%{view: view})

      {key, _secret} =
        socket.assigns.uploads_metadata
        |> Enum.to_list()
        |> List.first()
        |> elem(1)
        |> Map.get(:credentials)

      upload_conn =
        conn
        |> put_req_header("content-length", "4")
        |> put_req_header("content-range", "bytes 0-3/4")
        |> put_req_header("content-type", "text/plain")
        |> put("/upload_chunk/#{Base.encode16(key, case: :lower)}", IO.iodata_to_binary("1234"))

      assert upload_conn.status == 200

      render_upload(file, filename, 100)

      view
      |> form("#dialog-form", %{"dialog" => %{"text" => "Dialog message text"}})
      |> render_submit()

      assert has_element?(view, ".messageBlock", "Dialog message text")

      messages =
        socket.assigns.dialog
        |> Dialogs.read(socket.assigns.me)
        |> Enum.map(fn %PrivateMessage{} = message ->
          %{"id" => message.id, "index" => Integer.to_string(message.index)}
        end)
        |> Jason.encode!()

      render_hook(view, "dialog/download-messages", %{"messages" => messages})

      assert_push_event(view, "chat:redirect", %{url: url})

      conn = get(conn, url)

      assert conn.status == 200
      assert conn.resp_body =~ "Created by Zstream"
    end
  end
end
