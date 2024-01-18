defmodule ChatWebTest.MainLive.Admin.ZerotierSettingsTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveView, only: [send_update: 3]

  import Phoenix.LiveViewTest
  import LiveIsolatedComponent
  import Rewire

  alias ChatWeb.MainLive.Admin.ZerotierSettings

  defmodule PubSubMock do
    def broadcast(_topic, _event, payload) do
      with pid <- Process.whereis(ChatWebTest.MainLive.Admin.ZerotierSettingsTest.Agent),
           true <- is_pid(pid),
           true <- Process.alive?(pid) do
        Agent.update(pid, fn list -> [payload | list] end)
      end
    end
  end

  rewire(ZerotierSettings, [{Phoenix.PubSub, PubSubMock}])

  test "settings sunny flow" do
    %{}
    |> start_agent()
    |> mount_zerotier_settings_component
    |> assert_status_loading
    |> assert_networks_loading
    |> assert_requested(:list_networks)
    |> assert_requested(:info)
    |> send_status_update
    |> assert_status_rendered
    |> send_empty_networks_update
    |> assert_empty_networks_rendered
    |> join_network
    |> assert_requested({:join_network, "1d71939404f0a869"})
    |> assert_requested(:list_networks)
    |> assert_networks_loading
    |> send_networks_update
    |> assert_networks_rendered
    |> leave_network
    |> assert_requested({:leave_network, "1d71939404f0a869"})
    |> assert_requested(:list_networks)
    |> assert_networks_loading
  end

  defp mount_zerotier_settings_component(context) do
    assert {:ok, view, _html} =
             live_isolated_component(ZerotierSettings, assigns: %{id: :zerotier_settings})

    context
    |> Map.put(:view, view)
    |> Map.put(:component_id, :zerotier_settings)
  end

  def start_agent(context) do
    {:ok, agent_pid} =
      start_supervised(%{
        id: :agent,
        start: {Agent, :start_link, [fn -> [] end, [name: __MODULE__.Agent]]}
      })

    context
    |> Map.put(:agent_pid, agent_pid)
  end

  defp send_status_update(context) do
    send_update(context.view.pid, ZerotierSettings, %{
      id: context.component_id,
      status: info_json() |> ZerotierSettings.parse_info_response()
    })

    context
  end

  defp send_empty_networks_update(context) do
    send_update(context.view.pid, ZerotierSettings, %{
      id: context.component_id,
      list: []
    })

    context
  end

  defp join_network(context) do
    context.view
    |> element("#zerotier-add-network form")
    |> render_submit(%{network: "1d71939404f0a869"})

    context
  end

  defp send_networks_update(context) do
    send_update(context.view.pid, ZerotierSettings, %{
      id: context.component_id,
      list: networks_json() |> ZerotierSettings.parse_networks_response()
    })

    context
  end

  defp leave_network(context) do
    context.view
    |> element("#zerotier-network-1d71939404f0a869 button.t-leave-network")
    |> render_click()

    context
  end

  ### Assertions

  defp assert_status_loading(context) do
    assert has_element?(context.view, ".t-status", "loading...")
    context
  end

  defp assert_networks_loading(context) do
    assert has_element?(context.view, ".t-networks", "loading...")
    context
  end

  defp assert_status_rendered(context) do
    assert has_element?(context.view, ".t-status", "56bcbb9d9c")
    assert has_element?(context.view, ".t-status", "online")
    context
  end

  defp assert_empty_networks_rendered(context) do
    html = element(context.view, ".t-networks") |> render()
    refute html =~ "id=\"zerotier-network-"
    context
  end

  defp assert_networks_rendered(context) do
    assert has_element?(context.view, "#zerotier-network-1d71939404f0a869", "salseeg_first")

    context
  end

  defp assert_requested(context, command) do
    list = Agent.get(context.agent_pid, fn list -> list end)
    {cmd, pid} = list |> Enum.find({:error, nil}, &match?({^command, _}, &1))
    assert is_pid(pid)
    Agent.update(context.agent_pid, fn list -> Enum.reject(list, &match?({^command, _}, &1)) end)

    context
    |> Map.put(:command_sender_pid, pid)
    |> Map.put(:command_sent, cmd)
  end

  ### Fixture

  def info_json() do
    """
      {
       "address": "56bcbb9d9c",
       "clock": 1704914749230,
       "config": {
        "settings": {
         "allowTcpFallbackRelay": true,
         "forceTcpRelay": false,
         "listeningOn": [
          "192.168.25.1/48129",
          "192.168.0.247/48129",
          "192.168.25.1/9993",
          "192.168.0.247/9993",
          "192.168.25.1/43308",
          "192.168.0.247/43308"
         ],
         "portMappingEnabled": true,
         "primaryPort": 9993,
         "secondaryPort": 43308,
         "softwareUpdate": "disable",
         "softwareUpdateChannel": "release",
         "surfaceAddresses": [
          "188.191.238.67/35219",
          "188.191.238.67/48129",
          "188.191.238.67/43308"
         ],
         "tertiaryPort": 48129
        }
       },
       "online": true,
       "planetWorldId": 149604618,
       "planetWorldTimestamp": 1644592324813,
       "publicIdentity": "56bcbb9d9c:0:854b6ddfa98fe769a73f2d09c4606f3694645f66e26bdf32c43af7149cf2b402e588294400bc645ce902e3c1cce91f6b716db0f09e349e69d7506a9751e3c838",
       "tcpFallbackActive": false,
       "version": "1.12.2",
       "versionBuild": 0,
       "versionMajor": 1,
       "versionMinor": 12,
       "versionRev": 2
      }
    """
  end

  def networks_json do
    """
        [
         {
          "allowDNS": false,
          "allowDefault": false,
          "allowGlobal": false,
          "allowManaged": true,
          "assignedAddresses": [
           "10.147.20.50/24"
          ],
          "bridge": false,
          "broadcastEnabled": true,
          "dhcp": false,
          "dns": {
           "domain": "",
           "servers": []
          },
          "id": "1d71939404f0a869",
          "mac": "6a:fe:4c:bf:09:0f",
          "mtu": 2800,
          "multicastSubscriptions": [
           {
            "adi": 0,
            "mac": "01:00:5e:00:00:fb"
           },
           {
            "adi": 0,
            "mac": "33:33:00:00:00:01"
           }
          ],
          "name": "salseeg_first",
          "netconfRevision": 2,
          "nwid": "1d71939404f0a869",
          "portDeviceName": "ztrf2wgpdn",
          "portError": 0,
          "routes": [
           {
            "flags": 0,
            "metric": 0,
            "target": "10.147.20.0/24",
            "via": null
           }
          ],
          "status": "OK",
          "type": "PRIVATE"
         }
        ]
    """
  end
end
