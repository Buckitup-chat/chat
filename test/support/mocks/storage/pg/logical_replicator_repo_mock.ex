defmodule ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock do
  @moduledoc """
  `Ecto.Repo` stand-in for `Chat.Storage.Pg.LogicalReplicator` SQL tests.

  Every `query/1` is reported to `:test_pid` as `{:repo_query, sql}`. Answers come from
  `:query_results` (a script, one per call) when set, otherwise from `:query_result`.
  """

  @doc "Named setup: registers the test pid and resets the answers to `:ok`."
  def reset_repo_mock(_context) do
    Process.put(:test_pid, self())
    Process.put(:query_result, :ok)
    Process.delete(:query_results)
    :ok
  end

  def query(sql) do
    send(Process.get(:test_pid), {:repo_query, sql})

    case Process.get(:query_results) do
      [result | rest] ->
        Process.put(:query_results, rest)
        normalize_result(result)

      _ ->
        normalize_result(Process.get(:query_result, :ok))
    end
  end

  defp normalize_result(result) do
    case result do
      :ok -> {:ok, %{rows: [], num_rows: 0}}
      :error -> {:error, :query_failed}
      {:lag, bytes} -> {:ok, %{rows: [[bytes]], num_rows: 1}}
      :subscription_not_found -> {:ok, %{rows: [], num_rows: 0}}
      {:ok, _} = result -> result
      {:error, _} = result -> result
    end
  end
end
