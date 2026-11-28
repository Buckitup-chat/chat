defmodule ChatWeb.MainLive.IndexUsbDriveDumpTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers
  import ChatWeb.LiveTestHelpers.SyncRooms
  import Phoenix.LiveViewTest

  alias Chat.Sync.UsbDriveDumpRoom

  describe "usb drive dump" do
    setup %{conn: conn} do
      reset_sync_rooms()

      %{conn: conn}
      |> prepare_view()
      |> create_and_open_room()
    end

    test "starts the flow in existing room", %{view: view} do
      refute has_element?(view, ".t-dump-room")
      assert has_element?(view, "span div.t-dump-activate")

      view
      |> element("span div.t-dump-activate")
      |> render_click()

      refute has_element?(view, ".t-dump-room")
      refute has_element?(view, "span div.t-dump-activate")
      assert has_element?(view, ".t-dump-remove")
      html = render(view)
      assert html =~ "USB drive dump activated"
      assert html =~ "Insert empty USB drive"
      assert String.contains?(html, "5:00") or String.contains?(html, "4:59")

      Process.sleep(1000)
      assert render(view) =~ ~r/4:5\d/

      UsbDriveDumpRoom.dump()
      Process.sleep(100)

      refute has_element?(view, ".t-dump-room")
      refute has_element?(view, "span div.t-dump-activate")
      refute has_element?(view, ".t-dump-remove")
      assert render(view) =~ "USB drive dump activated"

      UsbDriveDumpRoom.mark_successful()
      UsbDriveDumpRoom.complete()
      Process.sleep(100)

      assert has_element?(view, ".t-dump-room")
      refute has_element?(view, "span div.t-dump-activate")
      assert has_element?(view, ".t-dump-remove")
      html = render(view)
      assert html =~ "USB drive dump activated"
      assert html =~ "Complete!"

      view
      |> element(".t-dump-room", "Dump room")
      |> render_click()

      refute has_element?(view, "span div.t-dump-activate")
      assert has_element?(view, ".t-dump-remove")
      html = render(view)
      assert html =~ "USB drive dump activated"
      assert html =~ "Complete!"
    end

    test "fails dumping", %{view: view} do
      refute has_element?(view, ".t-dump-room")
      assert has_element?(view, "span div.t-dump-activate")

      view
      |> element("span div.t-dump-activate")
      |> render_click()

      assert render(view) =~ "USB drive dump activated"

      UsbDriveDumpRoom.dump()
      Process.sleep(100)

      assert render(view) =~ "Dumping..."

      UsbDriveDumpRoom.complete()
      Process.sleep(100)

      assert render(view) =~ "Failed!"
      refute has_element?(view, ".t-dump-room")
      assert has_element?(view, ".t-dump-remove")

      view
      |> element(".t-dump-remove")
      |> render_click()

      refute has_element?(view, ".t-dump-room")
      refute render(view) =~ "USB drive dump activated"
    end

    test "stops the process early", %{view: view} do
      view
      |> element("span div.t-dump-activate")
      |> render_click()

      assert render(view) =~ "USB drive dump activated"
      assert has_element?(view, ".t-dump-remove")

      view
      |> element(".t-dump-remove")
      |> render_click()

      refute has_element?(view, ".t-dump-room")
      refute render(view) =~ "USB drive dump activated"

      view
      |> element("span div.t-dump-activate")
      |> render_click()

      assert render(view) =~ "USB drive dump activated"

      UsbDriveDumpRoom.remove()

      Process.sleep(100)

      refute render(view) =~ "USB drive dump activated"
    end
  end
end
