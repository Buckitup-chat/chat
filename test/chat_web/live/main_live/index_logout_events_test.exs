defmodule ChatWeb.MainLive.IndexLogoutEventsTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias ChatWeb.MainLive.Index

  @twelve_alnum "abcdefgh1234"

  setup [:prepare_view]

  describe "logout" do
    test "walks open → middle → share and closes", %{view: view} do
      render_hook(view, "logout-open")
      assert logout_step(view) == :initial

      render_hook(view, "logout-go-middle")
      assert logout_step(view) == :middle

      render_hook(view, "logout:toggle-password-visibility")
      render_hook(view, "logout:toggle-password-confirmation-visibility")

      assert %{is_password_visible: true, is_password_confirmation_visible: true} =
               assigns(view)

      render_hook(view, "logout-go-share")
      assert logout_step(view) == :share

      render_hook(view, "logout-close")
      assert logout_step(view) == nil
    end

    test "rejects a weak password and downloads with a good one", %{view: view} do
      render_hook(view, "logout-go-middle")

      render_hook(view, "logout-check-password", %{"logout" => password_form("short")})
      refute assigns(view).changeset.valid?

      render_hook(view, "logout-download-with-password", %{"logout" => password_form("short")})
      assert logout_step(view) == :middle

      render_hook(view, "logout-download-with-password", %{
        "logout" => password_form(@twelve_alnum)
      })

      assert logout_step(view) == :final
      assert_push_event(view, "chat:redirect", %{url: "/get/backup/" <> _})
    end

    test "insecure download goes final, key share message too", %{view: view} do
      render_hook(view, "logout-download-insecure")
      assert logout_step(view) == :final
      assert_push_event(view, "chat:redirect", %{url: "/get/backup/" <> _})

      render_hook(view, "logout-open")
      send(view.pid, {:key_shared, %{}})
      assert logout_step(view) == :final
    end

    test "wipe forgets the user", %{view: view} do
      render_hook(view, "logout-wipe")

      assert %{me: nil, need_login: true} = assigns(view)
      assert_push_event(view, "clear", %{})
    end
  end

  describe "data restore" do
    test "opens and closes", %{view: view} do
      render_hook(view, "open-data-restore")
      assert assigns(view).mode == :restore_data

      render_hook(view, "backup-file-submit")
      render_hook(view, "close-data-restore")
      assert assigns(view).mode == :lobby
    end
  end

  describe "info messages" do
    test "settings refresh messages reload settings", %{view: view} do
      for msg <- [:update_backup_settings, :update_cargo_settings, :update_media_settings] do
        send(view.pid, msg)
      end

      assert %{backup_settings: _, cargo_settings: _, media_settings: _} = assigns(view)
    end

    test "reset_rooms_to_backup clears the backup counter", %{view: view} do
      send(view.pid, :reset_rooms_to_backup)

      assert assigns(view).room_count_to_backup == 0
    end

    test "task replies are flushed and failed tasks rerun", %{view: view} do
      test_pid = self()
      ref = make_ref()

      send(view.pid, {ref, :ok})
      send(view.pid, {ref, {:error, fn _socket -> send(test_pid, :task_rerun) end, :boom}})

      assert_receive :task_rerun
      assert Process.alive?(view.pid)
    end

    test "db status message updates the status", %{view: view} do
      status = %{mode: :main, writable: :yes, flags: [backup: true]}
      send(view.pid, {:db_status, status})

      assert assigns(view).db_status == status
    end
  end

  describe "helpers" do
    test "message_of/1 tells room messages from dialog ones" do
      assert Index.message_of(%{author_key: "k"}) == "room"
      assert Index.message_of(%{}) == "dialog"
    end
  end

  # Helpers

  defp assigns(view), do: reload_view(%{view: view}).socket.assigns

  defp logout_step(view), do: assigns(view).logout_step

  defp password_form(password),
    do: %{"password" => password, "password_confirmation" => password}
end
