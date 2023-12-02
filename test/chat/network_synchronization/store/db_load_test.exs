defmodule Chat.NetworkSynchronization.Store.DbLoadTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization.Source
  alias Chat.NetworkSynchronization.Store

  rewire(Store, source_db_prefix: S1, source_table: S1, status_table: T1)

  test "loads list from DB" do
    %{}
    |> generate_some_db_sources(9)
    |> assert_lists_same_sources_sorted_by_id()
  end

  defp generate_some_db_sources(context, num) do
    for id <- num..1//-1 do
      Source.new(id)
      |> Map.put(:url, "http://a#{id}.example.com")
      |> then(&Chat.AdminDb.put({S1, id}, &1))

      id
    end
    |> Enum.sort()
    |> then(&Map.put(context, :db_sources_ids, &1))
  end

  defp assert_lists_same_sources_sorted_by_id(context) do
    Store.init()

    Store.list_sources_with_status()
    |> Enum.map(fn {%{id: id}, _} -> id end)
    |> tap(fn listed_ids ->
      assert listed_ids == context.db_sources_ids
    end)

    context
  end
end
