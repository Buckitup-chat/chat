defmodule Chat.NetworkSynchronization.Store.BasicStatusTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization.Status.CoolingStatus
  alias Chat.NetworkSynchronization.Store

  rewire(Store, source_db_prefix: S3, source_table: S3, status_table: T3)

  test "basic status added" do
    %{}
    |> add_sources(7)
    |> assert_sources_wo_status()
    |> set_them_cooling()
    |> assert_sources_cooling()
    |> delete_status_for_last(5)
    |> assert_rest_are_cooling()
  end

  defp add_sources(context, num) do
    Store.init()

    for _ <- 1..num do
      Store.add_source()
    end

    context
    |> Map.put(:added_amount, num)
  end

  defp set_them_cooling(context) do
    Store.list_sources_with_status()
    |> Enum.each(fn {source, nil} ->
      status = source |> CoolingStatus.new()
      Store.update_source_status(source.id, status)
    end)

    context
    |> Map.put(:set_as_cooling, true)
  end

  defp delete_status_for_last(context, amount) do
    Store.list_sources_with_status()
    |> Enum.slice(-amount..-1)
    |> Enum.each(fn {source, _status} ->
      Store.delete_source_status(source.id)
    end)

    context
    |> Map.put(:no_status_for_last, amount)
  end

  defp assert_sources_wo_status(context) do
    assert Store.list_sources_with_status()
           |> Enum.all?(fn {_, status} -> status == nil end)

    context
  end

  defp assert_sources_cooling(context) do
    assert Store.list_sources_with_status()
           |> Enum.all?(&match?({_, %CoolingStatus{}}, &1))

    context
  end

  defp assert_rest_are_cooling(context) do
    {cooling_list, nil_list} =
      Store.list_sources_with_status()
      |> Enum.split(context.added_amount - context.no_status_for_last)

    assert cooling_list |> Enum.all?(&match?({_, %CoolingStatus{}}, &1))
    assert nil_list |> Enum.all?(fn {_, status} -> status == nil end)

    context
  end
end
