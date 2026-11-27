defmodule ChatWebTest.MainLive.Admin.ZerotierSettingsTest do
  # Subscribes to the global zerotier topic, so it must not race other admin tests
  use ChatWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  alias ChatWeb.MainLive.Admin.ZerotierSettings

  @topic Application.compile_env!(:chat, :topic_to_zerotier)
  @info ~s({"address": "abc123", "online": true, "version": "1.12.2", "extra": 1})
  @networks ~s([{"id": "8056c2e21c000001", "name": "home", "status": "OK",
                 "assignedAddresses": ["10.0.0.2/24", "fd00::2/88"]}])

  setup do
    Phoenix.PubSub.subscribe(Chat.PubSub, @topic)
    on_exit(fn -> Phoenix.PubSub.unsubscribe(Chat.PubSub, @topic) end)
  end

  test "shows loading, then status and networks from zerotier replies" do
    view = mount_settings()

    assert has_element?(view, ".t-status", "loading...")
    assert has_element?(view, ".t-networks", "loading...")

    reply(view, :info, {:ok, @info})
    reply(view, :list_networks, {:ok, @networks})

    assert has_element?(view, ".t-status b", "online")
    assert has_element?(view, ".t-status i", "abc123")
    assert has_element?(view, ".t-status", "1.12.2")
    assert has_element?(view, "#zerotier-network-8056c2e21c000001", "home")
    assert has_element?(view, "#zerotier-network-8056c2e21c000001", "10.0.0.2/24, fd00::2/88")
  end

  test "offline status is rendered without bold marker" do
    view = mount_settings()

    reply(view, :info, {:ok, ~s({"address": "abc123", "online": false, "version": "1.0"})})

    assert has_element?(view, ".t-status", "offline")
    refute has_element?(view, ".t-status b")
  end

  test "error and unknown replies keep the loading state" do
    view = mount_settings()

    reply(view, :info, {:error, "not running"})
    reply(view, :list_networks, :unexpected)

    assert has_element?(view, ".t-status", "loading...")
    assert has_element?(view, ".t-networks", "loading...")
  end

  test "joining a network casts join and reloads the list" do
    view = mount_settings()
    reply(view, :list_networks, {:ok, "[]"})
    assert has_element?(view, ".t-networks button.t-open-new-network-form")

    view
    |> element("#zerotier-add-network form")
    |> render_submit(%{"network" => "8056c2e21c000002"})

    assert_receive {{:join_network, "8056c2e21c000002"}, caster}
    send(caster, :ok)
    assert has_element?(view, ".t-networks", "loading...")
    assert_receive {:list_networks, _}
  end

  test "leaving a network casts leave and reloads the list" do
    view = mount_settings()
    reply(view, :list_networks, {:ok, @networks})

    view
    |> element("#zerotier-network-8056c2e21c000001 .t-leave-network")
    |> render_click()

    assert_receive {{:leave_network, "8056c2e21c000001"}, _}
    assert has_element?(view, ".t-networks", "loading...")
  end

  test "parsers keep only known info fields and join cidrs" do
    assert %{"address" => "abc123", "online" => true, "version" => "1.12.2"} ==
             ZerotierSettings.parse_info_response(@info)

    assert [%{id: "8056c2e21c000001", name: "home", status: "OK", cidrs: cidrs}] =
             ZerotierSettings.parse_networks_response(@networks)

    assert cidrs == "10.0.0.2/24, fd00::2/88"
  end

  # Helpers

  defp mount_settings do
    {:ok, view, _} =
      live_isolated_component(ZerotierSettings, assigns: %{id: :zerotier_settings})

    view
  end

  # Both the disconnected and the connected mount send requests (networks are
  # re-requested on a timer), so answer the one started by the view process
  defp reply(view, command, response) do
    pid = await_request_from(view.pid, command)
    ref = Process.monitor(pid)
    send(pid, {command, response})
    # the task has sent its send_update to the view once it is down
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  defp await_request_from(view_pid, command) do
    assert_receive {^command, pid}

    if view_pid in callers(pid), do: pid, else: await_request_from(view_pid, command)
  end

  defp callers(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} -> Keyword.get(dict, :"$callers", [])
      nil -> []
    end
  end
end
