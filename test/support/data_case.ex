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

  defp ensure_electric_ready do
    unless ets_table_exists?(@ets_table) do
      :ets.new(@ets_table, [:named_table, :public])
    end

    for condition <- [:pg_lock_acquired, :replication_client_ready, :connection_pool_ready, :shape_log_collector_ready] do
      :ets.insert(@ets_table, {condition, {true, %{process: self()}}})
    end
  end

  defp ets_table_exists?(name) do
    :ets.whereis(name) != :undefined
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
