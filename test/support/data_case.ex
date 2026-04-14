defmodule ChatWeb.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Chat.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ChatWeb.DataCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Chat.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, {:shared, self()})
    end

    Process.put(:phoenix_sync_validating, true)
    Phoenix.Sync.Sandbox.start!(Chat.Repo, shared: not tags[:async])
    Process.delete(:phoenix_sync_validating)

    ensure_electric_ready()

    :ok
  end

  @stack_id "electric-embedded"
  @ets_table :"#{@stack_id}:status_monitor"
  @conditions [
    :pg_lock_acquired,
    :replication_client_ready,
    :connection_pool_ready,
    :shape_log_collector_ready
  ]

  defp ensure_electric_ready do
    ensure_ets_table()
    insert_ready_conditions()
  rescue
    ArgumentError ->
      ensure_ets_table()
      insert_ready_conditions()
  end

  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set])
        :ets.give_away(@ets_table, keeper_pid(), [])

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp insert_ready_conditions do
    for condition <- @conditions do
      :ets.insert(@ets_table, {condition, {true, %{process: self()}}})
    end
  end

  defp keeper_pid do
    case Process.whereis(:electric_test_ets_keeper) do
      pid when is_pid(pid) ->
        pid

      nil ->
        {:ok, pid} = Agent.start(fn -> :ok end, name: :electric_test_ets_keeper)
        pid
    end
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def assert_has_error(changeset, field, error_message) do
    assert is_struct(changeset, Ecto.Changeset)
    refute changeset.valid?
    assert error_message in Map.get(errors_on(changeset), field, [])
  end
end
