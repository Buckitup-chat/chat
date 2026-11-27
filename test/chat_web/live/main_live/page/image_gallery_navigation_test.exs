defmodule ChatWeb.MainLive.Page.ImageGalleryNavigationTest do
  use ChatWeb.ConnCase, async: true, group: :cubdb

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveView, only: [send_update: 3]
  import Phoenix.LiveViewTest
  import Support.RetryHelper

  alias Chat.Rooms
  alias ChatWeb.MainLive.Page.ImageGallery

  @wait 3_000

  describe "room image gallery" do
    setup [:prepare_view, :create_and_open_room]

    test "opening a middle image preloads both neighbours", %{
      conn: conn,
      view: view,
      socket: socket
    } do
      [first, middle, last] = upload_images(conn, view, socket, 3)

      open_gallery(view, "room", middle)

      assert_push_event(view, "gallery:preload", %{to: "preloadedList", url: "/get/image/" <> _})
      assert_current(view, middle)

      view |> element("#imageGallery #prev") |> render_click()
      assert_current(view, first)

      view |> element("#imageGallery #next") |> render_click()
      view |> element("#imageGallery #next") |> render_click()
      assert_current(view, last)
    end

    test "delivered current slide is preloaded again", %{conn: conn, view: view, socket: socket} do
      [image] = upload_images(conn, view, socket, 1)
      open_gallery(view, "room", image)
      assert_push_event(view, "gallery:preload", %{url: url})

      send_update(view.pid, ImageGallery, id: "imageGallery", action: :current_delivered)

      assert_push_event(view, "gallery:preload", %{to: "preloadedList", url: ^url})
    end

    test "preloading a closed gallery does nothing", %{view: view} do
      send_update(view.pid, ImageGallery, id: "imageGallery", action: :preload_next)
      send_update(view.pid, ImageGallery, id: "imageGallery", action: :preload_prev)

      refute view |> has_element?("#imageGallery #topPanel")
    end
  end

  describe "dialog image gallery" do
    setup [:prepare_view, :open_dialog]

    test "unknown message is shown as lost", %{view: view} do
      open_gallery(view, "dialog", %{id: "missing", index: 999_999})

      assert view |> has_element?("#imageGallery span", "The message is lost.")
      assert_current(view, %{id: "missing"})
    end
  end

  # Helpers

  defp assert_current(view, %{id: id}),
    do: assert(view |> has_element?("#imageGallery #topPanel span", id))

  defp open_gallery(view, chat_type, %{id: id, index: index}) do
    render_hook(view, "#{chat_type}/message/open-image-gallery", %{
      "id" => id,
      "index" => Integer.to_string(index)
    })
  end

  defp upload_images(conn, view, socket, count) do
    Enum.each(1..count, fn _ -> upload_image(conn, view) end)

    retry_until(@wait, fn -> assert count == socket |> read_messages() |> length() end)

    read_messages(socket)
  end

  defp read_messages(%{assigns: %{room: room, room_identity: identity}}),
    do: Rooms.read(room, identity)

  defp upload_image(conn, view) do
    %{entry: entry, file: file, filename: filename, socket: socket} = start_upload(%{view: view})
    %{credentials: {key, _secret}} = Map.fetch!(socket.assigns.uploads_metadata, entry.uuid)

    conn
    |> put_req_header("content-length", "4")
    |> put_req_header("content-range", "bytes 0-3/4")
    |> put_req_header("content-type", "text/plain")
    |> put("/upload_chunk/#{Base.encode16(key, case: :lower)}", "1234")
    |> then(&assert &1.status == 200)

    render_upload(file, filename, 100)
  end
end
