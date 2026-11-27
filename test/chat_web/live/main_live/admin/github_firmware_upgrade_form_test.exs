defmodule ChatWebTest.MainLive.Admin.GithubFirmwareUpgradeFormTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LiveIsolatedComponent
  import Support.Rewire
  import Support.RetryHelper

  alias ChatWeb.MainLive.Admin.GithubFirmwareUpgradeForm

  @outgoing_topic Application.compile_env!(:chat, :topic_to_platform)

  defmodule ReqMock do
    def get!(url, opts \\ [])

    def get!("https://api.github.com/repos/Buckitup-chat/platform/releases", _opts) do
      %Req.Response{
        status: 200,
        body: [
          %{
            "tag_name" => "v0.4.1",
            "assets" => [
              %{
                "name" => "platform.v0.4.1.buckitup.app.fw",
                "browser_download_url" =>
                  "https://github.com/Buckitup-chat/platform/releases/download/v0.4.1/platform.fw"
              }
            ]
          },
          %{
            "tag_name" => "v0.4.0",
            "assets" => [
              %{
                "name" => "platform.v0.4.0.buckitup.app.fw",
                "browser_download_url" =>
                  "https://github.com/Buckitup-chat/platform/releases/download/v0.4.0/platform.fw"
              }
            ]
          },
          %{
            "tag_name" => "v0.3.0",
            "assets" => [
              %{
                "name" => "source.zip",
                "browser_download_url" =>
                  "https://github.com/Buckitup-chat/platform/releases/download/v0.3.0/source.zip"
              }
            ]
          }
        ]
      }
    end
  end

  rewire(GithubFirmwareUpgradeForm, [{Req, ReqMock}])

  describe "loading and displaying releases" do
    test "shows loading state initially then displays releases" do
      {:ok, view, html} =
        live_isolated_component(GithubFirmwareUpgradeForm,
          assigns: %{id: :github_firmware_upgrade_form}
        )

      assert html =~ "Loading releases..."

      await_releases(view)

      html = render(view)
      assert html =~ "v0.4.1"
      assert html =~ "v0.4.0"
      # v0.3.0 has no .fw asset, so it should not appear
      refute html =~ "v0.3.0"

      assert has_element?(view, "select[name=\"release\"]")
      assert has_element?(view, "button", "Install")
    end

    test "can select a different release" do
      view = mount_form()

      view
      |> form("form", %{"release" => "v0.4.0"})
      |> render_change()

      assert has_element?(view, "option[value=\"v0.4.0\"][selected]")
    end

    test "clicking Install sends confirmation message to parent" do
      view = mount_form()

      view
      |> element("button", "Install")
      |> render_click()

      # LiveIsolatedComponent wraps messages sent via send/2
      assert_receive {:__live_isolated_component_handle_info_received__, _pid,
                      {:admin, {:github_upgrade_firmware_confirmation, %{tag: "v0.4.1", url: _}}}}
    end
  end

  describe "download flow" do
    test "shows downloading state with progress" do
      view = mount_form()

      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        action: :start_download
      )

      html = render(view)
      assert html =~ "Downloading firmware..."
      assert has_element?(view, "progress")

      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        platform_response: {:github_firmware_upgrade, {:download_progress, 50}}
      )

      html = render(view)
      assert html =~ "50%"

      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        platform_response: {:github_firmware_upgrade, {:download_progress, 100}}
      )

      html = render(view)
      assert html =~ "Applying firmware upgrade..."
      assert html =~ "The reboot will be performed automatically."
    end

    test "broadcasts upgrade request to platform" do
      Phoenix.PubSub.subscribe(Chat.PubSub, @outgoing_topic)

      view = mount_form()

      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        action: :start_download
      )

      render(view)

      assert_receive {:upgrade_firmware_from_url,
                      "https://github.com/Buckitup-chat/platform/releases/download/v0.4.1/platform.fw"}

      Phoenix.PubSub.unsubscribe(Chat.PubSub, @outgoing_topic)
    end
  end

  describe "error handling" do
    test "shows error when no releases found" do
      view = mount_form()

      # Simulate empty releases response
      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        fetched_releases: []
      )

      html = render(view)
      assert html =~ "No firmware releases found"
      assert has_element?(view, "button", "Retry")
    end

    test "shows error on fetch failure" do
      view = mount_form()

      # Simulate error response
      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        fetched_releases: {:error, "Network error"}
      )

      html = render(view)
      assert html =~ "Network error"
      assert has_element?(view, "button", "Retry")
    end

    test "can retry after error" do
      view = mount_form()

      # Simulate error
      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        fetched_releases: {:error, "Test error"}
      )

      html = render(view)
      assert html =~ "Test error"
      assert has_element?(view, "button", "Retry")

      view
      |> element("button", "Retry")
      |> render_click()

      await_releases(view)

      html = render(view)
      assert html =~ "v0.4.1"
      assert has_element?(view, "select[name=\"release\"]")
    end

    test "shows error when upgrade fails" do
      view = mount_form()

      Phoenix.LiveView.send_update(view.pid, GithubFirmwareUpgradeForm,
        id: :github_firmware_upgrade_form,
        platform_response: {:github_firmware_upgrade, {:error, :upgrade_failed}}
      )

      html = render(view)
      assert html =~ "Upgrade failed"
    end
  end

  # Helpers

  # The component fetches releases in a Task on mount. Wait for that update to land,
  # so a simulated send_update in the test can't be overwritten by it afterwards.
  defp mount_form do
    {:ok, view, _html} =
      live_isolated_component(GithubFirmwareUpgradeForm,
        assigns: %{id: :github_firmware_upgrade_form}
      )

    await_releases(view)
    view
  end

  defp await_releases(view),
    do: retry_until(2000, fn -> assert render(view) =~ "v0.4.1" end)
end
