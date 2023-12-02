defmodule SourceManagementTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Store

  rewire(Store, source_db_prefix: S6, source_table: S6, status_table: T6)
  rewire(Store, source_db_prefix: S6, source_table: S6, status_table: T6, as: StoreMock)
  rewire(NetworkSynchronization, Store: StoreMock)

  test "source created, edited, removed" do
    Store.init()

    %{}
    |> assert_empty()
    |> create_source()
    |> assert_as_newly_created()
    |> update_with_bad_fields()
    |> assert_as_newly_created()
    |> updated_with_correct_fields()
    |> assert_updated()
    |> remove_source()
    |> assert_empty()
  end

  defp create_source(context) do
    source = NetworkSynchronization.add_source()
    context |> Map.put(:just_created_source, source)
  end

  defp update_with_bad_fields(context) do
    NetworkSynchronization.update_source(context.just_created_source.id,
      strange_field: "some value",
      url: 1234,
      cooldown_hours: "12dr"
    )

    context
  end

  defp updated_with_correct_fields(context) do
    updated_source =
      NetworkSynchronization.update_source(context.just_created_source.id,
        url: "http://example.com",
        cooldown_hours: "12"
      )

    context |> Map.put(:updated_source, updated_source)
  end

  def remove_source(context) do
    NetworkSynchronization.remove_source(context.updated_source.id)
    context
  end

  defp assert_empty(context) do
    assert [] = NetworkSynchronization.synchronisation()
    context
  end

  defp assert_as_newly_created(context) do
    correct = [{context.just_created_source, nil}]
    assert correct == NetworkSynchronization.synchronisation()
    context
  end

  defp assert_updated(context) do
    correct = [{context.updated_source, nil}]
    assert correct == NetworkSynchronization.synchronisation()
    context
  end
end
