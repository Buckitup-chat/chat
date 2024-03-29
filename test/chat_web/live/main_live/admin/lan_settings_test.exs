defmodule ChatWebTest.MainLive.Admin.LanSettingsTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveView, only: [send_update: 3]
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent
  import Rewire

  alias ChatWeb.MainLive.Admin.LanSettings
  alias ChatWebTest.MainLive.Admin.LanSettingsTest, as: Test

  @outgoing_topic Application.compile_env!(:chat, :topic_to_platform)
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
    |> send_profile_update()
    |> assert_ip_rendered_and_mode_loading()
    |> send_known_profiles_update()
    |> assert_profiles_rendered_and_first_selected()
    |> flush_received_messages()
    |> change_profile_in_the_settings()
    |> assert_profile_change_and_profile_request_and_ip_request_received()
    |> assert_ip_rendered_and_mode_loading()
    |> send_profile_update_to_second()
    |> assert_profile_rendered_and_second_selected()
    |> unsubscribe_from_outgoing_pubsub()
  end

  defp mount_lan_settings_component(context) do
    assert {:ok, view, _} = live_isolated_component(LanSettings, assigns: %{id: :lan_settings})

    context
    |> Map.put(:view, view)
    |> Map.put(:component_id, :lan_settings)
  end

  defp send_ip_update(context) do
    context
    |> send_component_update(:ip, "123.45.67.89")
  end

  defp send_profile_update(context) do
    context
    |> send_component_update(:profile, :no_internet)
  end

  defp send_known_profiles_update(context) do
    context
    |> send_component_update(:known_profiles, [:no_internet, :internet])
  end

  defp send_profile_update_to_second(context) do
    context
    |> send_component_update(:profile, :internet)
  end

  defp send_component_update(context, key, value) do
    send_update(context.view.pid, LanSettings, %{:id => context.component_id, key => value})
    context
  end

  defp change_profile_in_the_settings(context) do
    profile = :internet

    context.view
    |> element("section:nth-of-type(2) form")
    |> render_change(%{"mode" => profile})

    context
    |> Map.put(:assigned_profile, profile)
  end

  defp assert_loading_for_ip_and_mode(context) do
    assert context.view |> has_element?("section:nth-of-type(1) label", "IP")
    assert context.view |> has_element?("section:nth-of-type(1)", "loading...")

    assert context.view |> has_element?("section:nth-of-type(2) label", "Mode")
    assert context.view |> has_element?("section:nth-of-type(2)", "loading...")
    context
  end

  defp assert_requests_to_platform_received(context) do
    assert_receive :lan_ip
    assert_receive :lan_profile
    assert_receive :lan_known_profiles
    context
  end

  defp assert_profile_change_and_profile_request_and_ip_request_received(context) do
    assert_receive {:lan_set_profile, :internet}
    assert_receive :lan_profile
    assert_receive :lan_ip
    context
  end

  defp assert_ip_rendered_and_mode_loading(context) do
    assert context.view |> has_element?("section:nth-of-type(1)", "123.45.67.89")
    assert context.view |> has_element?("section:nth-of-type(2)", "loading...")
    context
  end

  defp assert_profiles_rendered_and_first_selected(context) do
    assert context.view
           |> has_element?("section:nth-of-type(2) select option[selected]", "No internet")

    assert context.view |> has_element?("section:nth-of-type(2) select option", "Internet")
    context
  end

  defp assert_profile_rendered_and_second_selected(context) do
    assert context.view
           |> has_element?("section:nth-of-type(2) select option[selected]", "Internet")

    assert context.view |> has_element?("section:nth-of-type(2) select option", "No internet")
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

  defp flush_received_messages(context) do
    receive do
      _ -> flush_received_messages(context)
    after
      0 -> context
    end
  end

  defp start_test_pubsub(context) do
    start_supervised({Phoenix.PubSub, name: @pubsub_name})

    {:ok, context}
  end
end
