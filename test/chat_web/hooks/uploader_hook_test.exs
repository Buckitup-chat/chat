defmodule ChatWeb.Hooks.UploaderHookTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.UploadEntry

  describe "on_mount/4" do
    test "allows file upload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      state = :sys.get_state(view.pid)
      assert state.socket.assigns.uploads.file
    end

    test "handles upload events", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})
      open_dialog(%{view: view})
      %{entry: %UploadEntry{ref: ref, uuid: uuid}} = start_upload(%{view: view})

      render_hook(view, "upload:pause", %{"uuid" => uuid})
      render_hook(view, "upload:resume", %{"uuid" => uuid})
      render_hook(view, "upload:cancel", %{"ref" => ref, "uuid" => uuid})
    end
  end
end
