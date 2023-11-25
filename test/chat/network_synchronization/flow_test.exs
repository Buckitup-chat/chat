defmodule Chat.NetworkSynchronization.FlowTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.NetworkSynchronization
  alias Chat.NetworkSynchronization.Flow
  alias Chat.NetworkSynchronization.Status
  alias Chat.NetworkSynchronization.Store

  defmodule RetrievalMock do
    def remote_keys(""), do: {:error, "No host"}
    def remote_keys(_url), do: {:ok, [1, 2, 3, 4, 5]}
    def reject_known(keys), do: keys
    def retrieve_key(_url, _key), do: :skip
    def finalize(), do: :ok
  end

  rewire(Store, source_db_prefix: S4, source_table: S4, status_table: T4)

  rewire(Store, source_db_prefix: S4, source_table: S4, status_table: T4, as: StoreMock)
  rewire(Flow, [{Chat.NetworkSynchronization.Retrieval, RetrievalMock}, {Store, StoreMock}])
  rewire(NetworkSynchronization, Store: StoreMock)

  test "full cycle" do
    %{}
    |> make_empty_source
    |> assert_no_status
    |> start_stored_synchronization
    |> assert_in_cooling
    |> start_synchronization
    |> assert_in_error
    |> back_to_editing
    |> assert_no_status
    |> fix_source
    |> assert_source_with_url
    |> start_synchronization
    |> assert_in_updating
    |> update_a_few(2)
    |> assert_in_updating_with_progress
    |> update_all
    |> assert_in_updating_finished
    |> switch_in_cooldown
    |> assert_in_cooling
    |> back_to_editing
    |> assert_no_status
  end

  defp make_empty_source(context) do
    source = NetworkSynchronization.add_source()

    context
    |> Map.put(:source, source)
  end

  defp start_synchronization(context) do
    source =
      context.source
      |> Map.put(:started?, true)
      |> Store.update_source()

    Flow.start_synchronization(source, ok: &{&1, &2}, error: &{&1})
    |> case do
      {_status, keys} ->
        context
        |> Map.put(:source, source)
        |> Map.put(:keys, keys)

      _ ->
        context
        |> Map.put(:source, source)
    end
  end

  defp start_stored_synchronization(context) do
    source =
      context.source
      |> Map.put(:started?, true)
      |> Store.update_source()

    Flow.start_half_cooled(source)

    context
    |> Map.put(:source, source)
  end

  defp back_to_editing(context) do
    Store.delete_source_status(context.source.id)

    context.source
    |> Map.put(:started?, false)
    |> Store.update_source()
    |> then(&Map.put(context, :source, &1))
  end

  defp fix_source(context) do
    context.source
    |> Map.put(:url, "http://example.com")
    |> Store.update_source()
    |> then(&Map.put(context, :source, &1))
  end

  defp update_a_few(context, amount) do
    NetworkSynchronization.synchronisation()
    |> Enum.find(fn {source, _} -> source.id == context.source.id end)
    |> then(fn {source, status} ->
      %Status.UpdatingStatus{} = status

      status
      |> Map.put(:done, amount)
      |> then(&Store.update_source_status(source.id, &1))
    end)

    context
    |> Map.put(:amount_updated, amount)
  end

  defp update_all(context) do
    {source, status} =
      NetworkSynchronization.synchronisation()
      |> Enum.find(fn {source, _} -> source.id == context.source.id end)

    context.keys
    |> Enum.drop(context.amount_updated)
    |> Enum.reduce(status, fn key, status ->
      Flow.start_key_retrieval(status, source, key)
    end)

    context
  end

  defp switch_in_cooldown(context) do
    Flow.start_cooling(context.source)
    context
  end

  defp assert_no_status(context) do
    id = context.source.id
    assert [{%{id: ^id, started?: false}, nil}] = NetworkSynchronization.synchronisation()

    context
  end

  defp assert_in_error(context) do
    assert [{%{started?: true}, %Status.ErrorStatus{}}] = NetworkSynchronization.synchronisation()
    context
  end

  defp assert_source_with_url(context) do
    assert [{%{url: url}, _}] = NetworkSynchronization.synchronisation()
    assert url != ""
    context
  end

  defp assert_in_updating(context) do
    assert [{%{started?: true}, %Status.UpdatingStatus{done: 0}}] =
             NetworkSynchronization.synchronisation()

    context
  end

  defp assert_in_updating_with_progress(context) do
    amount = context.amount_updated
    assert [{_, %Status.UpdatingStatus{done: ^amount}}] = NetworkSynchronization.synchronisation()
    context
  end

  defp assert_in_updating_finished(context) do
    assert [{%{}, %Status.UpdatingStatus{done: count, total: count}}] =
             NetworkSynchronization.synchronisation()

    context
  end

  defp assert_in_cooling(context) do
    assert [{%{started?: true}, %Status.CoolingStatus{}}] =
             NetworkSynchronization.synchronisation()

    context
  end
end
