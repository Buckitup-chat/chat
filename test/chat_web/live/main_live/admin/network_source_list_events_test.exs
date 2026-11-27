defmodule ChatWebTest.MainLive.Admin.NetworkSourceListEventsTest do
  # FakeSync is a named Agent shared by the rewired component
  use ChatWeb.ConnCase, async: false
  import Phoenix.LiveView, only: [send_update: 3]
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent
  import Rewire

  alias Chat.NetworkSynchronization.Source
  alias Chat.NetworkSynchronization.Status

  defmodule FakeSync do
    @moduledoc "Stands in for Chat.NetworkSynchronization, records the calls"
    use Agent

    def start_link(list),
      do: Agent.start_link(fn -> %{list: list, calls: []} end, name: __MODULE__)

    def set_list(list), do: Agent.update(__MODULE__, &%{&1 | list: list})
    def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

    def synchronisation, do: Agent.get(__MODULE__, & &1.list)
    def add_source, do: record(:add_source)
    def remove_source(id), do: record({:remove_source, id})
    def start_source(id), do: record({:start_source, id})
    def stop_source(id), do: record({:stop_source, id})
    def update_source(id, fields), do: record({:update_source, id, fields})

    defp record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})
  end

  rewire(ChatWeb.MainLive.Admin.NetworkSourceList,
    NetworkSynchronization: FakeSync,
    as: SourceList
  )

  @peer "http://peer.local:4000"

  setup do
    start_supervised!({FakeSync, [{source(7, @peer), nil}]})
    :ok
  end

  test "add, delete, start and stop call the synchronization and reload the list" do
    view = mount_list()
    FakeSync.set_list([{source(7, @peer), nil}, {source(8, ""), nil}])

    view |> element("button[phx-click=add]") |> render_click()
    assert has_element?(view, "#network-source-8")

    view |> element("#network-source-7 button[phx-click=delete]") |> render_click()

    FakeSync.set_list([{source(7, @peer), Status.SynchronizingStatus.new()}])
    view |> element("#network-source-7 button[phx-click=start-sync]") |> render_click()
    view |> element("#network-source-7 button[phx-click=stop-item]") |> render_click()

    assert FakeSync.calls() == [
             :add_source,
             {:remove_source, 7},
             {:start_source, 7},
             {:stop_source, 7}
           ]
  end

  test "editing a source updates its url and cooldown" do
    view = mount_list()

    view
    |> element("#network-source-7 form")
    |> render_change(%{"item" => %{"7" => %{"url" => "http://other", "cooldown_hours" => "3"}}})

    assert FakeSync.calls() == [{:update_source, 7, [url: "http://other", cooldown_hours: "3"]}]
  end

  test "status update replaces the status of a known source" do
    view = mount_list()

    update(view, status_update: {7, Status.ErrorStatus.new("unreachable")})

    assert has_element?(view, "#network-source-7", "unreachable")
  end

  test "status update for an unknown source pulls it from the synchronization" do
    view = mount_list()
    FakeSync.set_list([{source(3, "http://new"), nil}, {source(7, @peer), nil}])

    update(view, status_update: {3, Status.SynchronizingStatus.new()})

    assert view |> render() |> String.split("network-source-") |> length() == 3
    assert has_element?(view, "#network-source-3")
    assert render(view) =~ ~r/network-source-3.*network-source-7/s
  end

  test "electric shape statuses are shown per peer" do
    view = mount_list()
    refute has_element?(view, "#network-source-7 .font-mono")

    for {shape, status} <- [
          users: %Status.LiveStatus{},
          dialogs: %Status.SynchronizingStatus{},
          files: %Status.ErrorStatus{reason: "boom"},
          rooms: :whatever
        ] do
      update(view, electric_status_update: {@peer, shape, status})
    end

    assert has_element?(view, "#network-source-7 .text-green-700", "live")
    assert has_element?(view, "#network-source-7 .text-gray-500", "syncing...")
    assert has_element?(view, "#network-source-7 .text-red-700", "err: boom")
    assert has_element?(view, "#network-source-7 .text-gray-500", "? unknown")
  end

  test "electric statuses of another peer or a hostless url are not shown" do
    FakeSync.set_list([{source(7, @peer), nil}, {source(9, "not a url"), nil}])
    view = mount_list()

    update(view, electric_status_update: {"http://elsewhere:4000", :users, %Status.LiveStatus{}})

    refute has_element?(view, ".font-mono")
  end

  # Helpers

  defp mount_list do
    {:ok, view, _} = live_isolated_component(SourceList, assigns: %{id: :network_sources})
    view
  end

  defp update(view, assigns),
    do: send_update(view.pid, SourceList, Keyword.put(assigns, :id, :network_sources))

  defp source(id, url), do: id |> Source.new() |> struct(url: url)
end
