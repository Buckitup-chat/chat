defmodule Chat.Storage.Pg.LogicalReplicatorLagTest do
  use ExUnit.Case, async: true

  import ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock, only: [reset_repo_mock: 1]

  alias Chat.Storage.Pg.LogicalReplicator
  alias ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock, as: RepoMock

  @moduletag :capture_log

  setup :reset_repo_mock

  describe "check_replication_lag/2" do
    test "returns lag in bytes when subscription exists" do
      assert {:ok, 1024} = lag_when_repo_answers({:lag, 1024})
      assert_received {:repo_query, sql}
      assert sql =~ "pg_stat_subscription"
      assert sql =~ "subname = 'my_subscription'"
      assert sql =~ "pg_wal_lsn_diff(latest_end_lsn, received_lsn)"
    end

    test "returns zero lag when no lag" do
      assert {:ok, 0} = lag_when_repo_answers({:lag, 0})
    end

    test "returns error when subscription not found" do
      assert {:error, :subscription_not_found} = lag_when_repo_answers(:subscription_not_found)
    end

    test "returns error when query fails" do
      assert {:error, :query_failed} = lag_when_repo_answers(:error)
    end

    test "uses pg_wal_lsn_diff with latest_end_lsn and received_lsn" do
      lag_when_repo_answers({:lag, 2048})

      assert_received {:repo_query, sql}
      assert sql =~ "pg_wal_lsn_diff(latest_end_lsn, received_lsn)"
      assert sql =~ "COALESCE"
    end

    test "truncates float lag to integer" do
      assert {:ok, 1024} = lag_when_repo_answers({:lag, 1024.5})
    end
  end

  defp lag_when_repo_answers(query_result) do
    Process.put(:query_result, query_result)
    LogicalReplicator.check_replication_lag(RepoMock, "my_subscription")
  end
end
