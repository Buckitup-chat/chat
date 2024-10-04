defmodule Chat.NetworkSynchronization.Store.SourceOperationsTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization.Store

  rewire(Store, source_db_prefix: S2, source_table: S2, status_table: T2)

  test "saving new sources in db" do
    %{}
    |> enlist_sources(9)
    |> assert_all_stored_in_db()
    |> update_cooldown_for_id(7)
    |> assert_all_stored_in_db()
    |> delete_source_id(3)
    |> assert_all_stored_in_db()
  end

  defp enlist_sources(context, num) do
    Store.init()

    for _ <- 1..num do
      Store.add_source()
    end
    |> then(&Map.put(context, :added_sources, &1))
  end

  defp update_cooldown_for_id(context, id) do
    source =
      context.added_sources
      |> Enum.find(&(&1.id == id))

    updated_source =
      %{source | cooldown_hours: source.cooldown_hours * 2}
      |> Store.update_source()

    context
    |> Map.put(:updated_sources, [updated_source | Map.get(context, :updated_sources, [])])
  end

  defp delete_source_id(context, target_id) do
    Store.list_sources_with_status()
    |> Enum.find(fn {%{id: id}, _} -> target_id == id end)
    |> elem(0)
    |> Store.delete_source()

    context
    |> Map.put(:deleted_source_ids, [target_id, context[:deleted_source_ids] || []])
  end

  defp assert_all_stored_in_db(context) do
    deleted_ids = Map.get(context, :deleted_source_ids, [])
    added_sources = Map.get(context, :added_sources, [])

    updated_sources =
      Map.get(context, :updated_sources, [])
      |> Map.new(fn source -> {source.id, source} end)

    correct_list =
      added_sources
      |> Enum.map(fn added ->
        Map.get(updated_sources, added.id, added)
      end)
      |> Enum.reject(&(&1.id in deleted_ids))

    ets_list =
      Store.list_sources_with_status()
      |> Enum.map(&first_in_pair/1)

    assert correct_list == ets_list

    db_list =
      Chat.AdminDb.list({{S2, 0}, {S2, nil}})
      |> Stream.map(&last_in_pair/1)
      |> Enum.sort_by(& &1.id)

    assert correct_list == db_list

    context
  end

  defp first_in_pair({first, _}), do: first
  defp last_in_pair({_, last}), do: last
end
