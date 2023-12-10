defmodule ChatWebTest.MainLive.Admin.LanSettingsTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent
  import Rewire

  alias ChatWeb.MainLive.Admin.LanSettings
  alias ChatWebTest.MainLive.Admin.LanSettingsTest, as: Test

  @outgoing_topic "chat->platform"
  @pubsub_name Test.PubSub

  defmodule AdminPanelMock do
    def request_platform(msg), do: Phoenix.PubSub.broadcast(Test.PubSub, "chat->platform", msg)
  end
  rewire(LanSettings, [{ChatWeb.MainLive.Page.AdminPanel, AdminPanelMock}])

  setup [:start_test_pubsub]

  test "lan settings working" do
    %{}
    |> subscribe_to_outgoing_pubsub()
    |> mount_lan_settings_component()
    |> assert_loading_for_ip_and_mode()
    |> assert_requests_to_platform_received()
    |> send_ip_update()
    |> assert_ip_rendered_and_mode_loading()
    #    |> send_profile_update()
    #    |> assert_ip_rendered_and_mode_loading()
    #    |> send_known_profiles_update()
    #    |> assert_profiles_rendered_and_first_selected()
    #    |> change_profile_in_the_settings()
    #    |> assert_profile_change_and_profile_request_received()
    #    |> assert_ip_rendered_and_mode_loading()
    #    |> send_profile_update_to_second()
    #    |> assert_profile_rendered_and_second_selected()
    |> unsubscribe_from_outgoing_pubsub()
  end

  defp mount_lan_settings_component(context) do
    assert {:ok, view, _} = live_isolated_component(LanSettings, id: :lan_settings)

    context
    |> Map.put(:view, view)
    |> Map.put(:component_id, :lan_settings)
  end

  defp send_ip_update(context) do
    ip = "123.45.67.89"
    view = context.view |> live_assign(:ip, ip)

    context
    |> Map.put(:view, view)
    |> Map.put(:assigned_ip, ip)
  end

  defp assert_loading_for_ip_and_mode(context) do
    assert context.view |> has_element?("section:nth-of-type(1) label", "IP")
    assert context.view |> has_element?("section:nth-of-type(1) span", "loading...")

    assert context.view |> has_element?("section:nth-of-type(2) label", "Mode")
    assert context.view |> has_element?("section:nth-of-type(2) span", "loading...")
    context
  end

  defp assert_requests_to_platform_received(context) do
    assert_receive {:platform_request, :lan_ip}
    assert_receive {:platform_request, :lan_profile}
    assert_receive {:platform_request, :lan_known_profiles}
    context
  end

  defp assert_ip_rendered_and_mode_loading(context) do
    assert context.view |> has_element?("section:nth-of-type(1) span", "123.45.67.89")
    assert context.view |> has_element?("section:nth-of-type(2) span", "Loading...")
    context
  end

  defp subscribe_to_outgoing_pubsub(context) do
    Phoenix.PubSub.subscribe(@pubsub_name, @outgoing_topic)
    context
  end

  defp unsubscribe_from_outgoing_pubsub(context) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, @outgoing_topic)
    context
  end

  defp start_test_pubsub(context) do
    start_supervised({Phoenix.PubSub, name: @pubsub_name})

    {:ok, context}
  end
end
