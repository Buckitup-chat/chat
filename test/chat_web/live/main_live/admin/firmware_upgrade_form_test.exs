defmodule ChatWebTest.MainLive.Admin.FirmwareUpgradeFormTest do
  # Listens on the global platform topic, so it must not race other admin tests
  use ChatWeb.ConnCase, async: false
  import Phoenix.LiveView, only: [send_update: 3]
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  alias ChatWeb.MainLive.Admin.FirmwareUpgradeForm

  @outgoing_topic Application.compile_env!(:chat, :topic_to_platform)
  @firmware "firmware image bytes"

  setup do
    Phoenix.PubSub.subscribe(Chat.PubSub, @outgoing_topic)
    on_exit(fn -> Phoenix.PubSub.unsubscribe(Chat.PubSub, @outgoing_topic) end)
  end

  test "upload shows progress, then the Upgrade button" do
    view = mount_form()
    assert has_element?(view, "#firmware-upgrade-form input[value=Upload]")

    upload = start_upload(view)
    assert has_element?(view, "div", "Uploading...")
    refute has_element?(view, "#firmware-upgrade-form input[value=Upload]")

    render_upload(upload, "image.fw", 50)
    assert has_element?(view, "progress[value='50']")
    refute has_element?(view, "button", "Upgrade")

    render_upload(upload, "image.fw", 50)
    assert has_element?(view, "button", "Upgrade")
  end

  test "cancelling the upload returns to the Upload button" do
    view = mount_form()
    view |> start_upload() |> render_upload("image.fw", 50)

    view |> element("button[phx-click=cancel-upload]") |> render_click()

    assert has_element?(view, "#firmware-upgrade-form input[value=Upload]")
    refute has_element?(view, "progress")
  end

  # Called directly: the isolated view re-runs update/2 on every handle_info,
  # and allow_upload refuses to re-run while the uploaded entry is still active
  test "Upgrade asks the panel for confirmation" do
    view = uploaded_form()
    assert has_element?(view, "button[phx-click=upgrade]", "Upgrade")

    assert {:noreply, %Phoenix.LiveView.Socket{}} =
             FirmwareUpgradeForm.handle_event("upgrade", %{}, %Phoenix.LiveView.Socket{})

    assert_received {:admin, :upgrade_firmware_confirmation}
    refute_receive {:upgrade_firmware, _}, 100
  end

  test "upgrade step sends the uploaded firmware to the platform" do
    view = uploaded_form()

    send_update(view.pid, FirmwareUpgradeForm, id: :firmware_upgrade_form, step: :upgrade)

    assert_receive {:upgrade_firmware, @firmware}
    assert render(view) =~ "Upgrading..."
  end

  # Helpers

  defp mount_form do
    {:ok, view, _} =
      live_isolated_component(FirmwareUpgradeForm, assigns: %{id: :firmware_upgrade_form})

    view
  end

  defp uploaded_form do
    view = mount_form()
    view |> start_upload() |> render_upload("image.fw")
    view
  end

  defp start_upload(view) do
    upload =
      file_input(view, "#firmware-upgrade-form", :config, [
        %{name: "image.fw", content: @firmware, type: "application/octet-stream"}
      ])

    view |> form("#firmware-upgrade-form") |> render_change()
    upload
  end
end
