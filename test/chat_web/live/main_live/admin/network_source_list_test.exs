defmodule ChatWebTest.MainLive.Admin.NetworkSourceListTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  alias Chat.NetworkSynchronization.Source
  alias Chat.NetworkSynchronization.Status

  alias ChatWeb.MainLive.Admin.NetworkSourceList

  test "empty list has button to add a source" do
    %{list: empty_list()}
    |> start_network_sources_list()
    |> assert_has_add_button()
  end

  test "new source has fields and buttons to delete and start" do
    %{list: new_list()}
    |> start_network_sources_list()
    |> assert_has_source_edit_fields()
    |> assert_has_source_delete_button()
    |> assert_has_source_start_button()
    |> assert_has_add_button()
  end

  test "synchronization has button to stop" do
    %{list: synchronizing_list()}
    |> start_network_sources_list()
    |> assert_has_source_stop_button()
    |> assert_has_add_button()
  end

  test "error has a message and button to stop" do
    %{list: error_list()}
    |> start_network_sources_list()
    |> assert_has_error_reason()
    |> assert_has_source_stop_button()
    |> assert_has_add_button()
  end

  test "cooldown has a message and a button to stop" do
    %{list: cooling_list()}
    |> start_network_sources_list()
    |> assert_has_source_stop_button()
    |> assert_has_add_button()
  end

  test "updating has a progressbar and a button to stop" do
    %{list: updating_list()}
    |> start_network_sources_list()
    |> assert_has_progress_bar()
    |> assert_has_source_stop_button()
    |> assert_has_add_button()
  end

  defp start_network_sources_list(context) do
    assert {:ok, view, _} = live_isolated_component(NetworkSourceList, id: :network_souces)
    view = view |> live_assign(list: context.list)
    Map.put(context, :view, view)
  end

  defp empty_list, do: []
  defp new_list, do: [{Source.new(123), nil}]
  defp error_list, do: [{Source.new(123), Status.ErrorStatus.new("theReason")}]
  defp synchronizing_list, do: [{Source.new(123), Status.SynchronizingStatus.new()}]
  defp cooling_list, do: [{Source.new(123), Status.CoolingStatus.new(Source.new(1))}]

  defp updating_list,
    do: [{Source.new(123), Status.UpdatingStatus.new([]) |> struct(total: 5, done: 3)}]

  defp assert_has_add_button(context) do
    assert context.view |> has_element?("div[data-phx-component] > button[phx-click=add]", "Add")
    context
  end

  defp assert_has_source_edit_fields(context) do
    assert context.view |> has_element?("#network-source-123 input[type=text]")
    assert context.view |> has_element?("#network-source-123 input[type=number]")
    assert context.view |> has_element?("#network-source-123 form[phx-change=item-change]")
    context
  end

  defp assert_has_source_delete_button(context) do
    assert context.view |> has_element?("#network-source-123 button[phx-click=delete]", "Delete")
    context
  end

  defp assert_has_source_start_button(context) do
    assert context.view
           |> has_element?("#network-source-123 button[phx-click=start-sync]", "Start")

    context
  end

  defp assert_has_error_reason(context) do
    assert context.view |> has_element?("#network-source-123 div", "theReason")
    context
  end

  defp assert_has_progress_bar(context) do
    assert context.view |> has_element?("#network-source-123 progress[max=5]")
    context
  end

  defp assert_has_source_stop_button(context) do
    assert context.view |> has_element?("#network-source-123 button[phx-click=stop-item]", "Stop")
    context
  end

  #  test "test" do
  #    one_list = [{Source.new(1), nil}]
  #
  #    live_isolated_component(NetworkSourceList, id: :network_souces)
  #    |> then(fn {:ok, view, _} -> view end)
  #    |> live_assign(list: one_list)
  #    |> render()
  #    |> dbg()
  #
  #    #     render_component(NetworkSourceList, id: 123, list: one_list)
  #    #     |> dbg()
  #
  #    #     NetworkSourceList.render(%{list: one_list, myself: "me"})
  #    #     |> rendered_to_string()
  #    #     |> dbg()
  #  end
end
