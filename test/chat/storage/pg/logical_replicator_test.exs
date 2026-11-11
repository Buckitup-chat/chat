defmodule Chat.Storage.Pg.LogicalReplicatorTest do
  use ExUnit.Case, async: true

  alias Chat.Storage.Pg.LogicalReplicator

  @moduletag :capture_log

  # Mock Ecto.Repo for testing SQL execution
  defmodule RepoMock do
    def query(sql) do
      test_pid = Process.get(:test_pid)
      send(test_pid, {:repo_query, sql})

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

  setup do
    test_pid = self()
    Process.put(:test_pid, test_pid)
    Process.put(:query_result, :ok)
    Process.delete(:query_results)
    :ok
  end

  describe "create_publication/3" do
    test "creates publication with specified tables" do
      result =
        LogicalReplicator.create_publication(
          RepoMock,
          ["users", "messages"],
          "my_publication"
        )

      assert :ok = result
      assert_received {:repo_query, sql}
      assert sql =~ "CREATE PUBLICATION my_publication"
      assert sql =~ "FOR TABLE users, messages"
      assert sql =~ "IF NOT EXISTS"
    end

    test "creates publication with single table" do
      result =
        LogicalReplicator.create_publication(
          RepoMock,
          ["users"],
          "users_pub"
        )

      assert :ok = result
      assert_received {:repo_query, sql}
      assert sql =~ "FOR TABLE users"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      result =
        LogicalReplicator.create_publication(
          RepoMock,
          ["users"],
          "my_publication"
        )

      assert {:error, :query_failed} = result
    end

    test "uses DO $$ block for idempotency" do
      LogicalReplicator.create_publication(
        RepoMock,
        ["users"],
        "my_publication"
      )

      assert_received {:repo_query, sql}
      assert sql =~ "DO $$"
      assert sql =~ "END $$"
    end
  end

  describe "create_subscription/5" do
    test "creates subscription with default options" do
      result =
        LogicalReplicator.create_subscription(
          RepoMock,
          "host=localhost port=5432 dbname=chat user=replicator password=secret",
          "source_publication",
          "my_subscription"
        )

      assert :ok = result
      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      assert exists_sql =~ "subname = 'my_subscription'"

      assert_received {:repo_query, create_sql}
      assert create_sql =~ "CREATE SUBSCRIPTION my_subscription"

      assert create_sql =~
               "CONNECTION 'host=localhost port=5432 dbname=chat user=replicator password=secret'"

      assert create_sql =~ "PUBLICATION source_publication"
      assert create_sql =~ "copy_data = false"
      assert create_sql =~ "enabled = true"
    end

    test "creates subscription with copy_data enabled" do
      result =
        LogicalReplicator.create_subscription(
          RepoMock,
          "host=localhost port=5432 dbname=chat user=replicator",
          "source_publication",
          "my_subscription",
          copy_data: true
        )

      assert :ok = result
      assert_received {:repo_query, _exists_sql}
      assert_received {:repo_query, create_sql}
      assert create_sql =~ "copy_data = true"
    end

    test "creates subscription with enabled false" do
      result =
        LogicalReplicator.create_subscription(
          RepoMock,
          "host=localhost port=5432 dbname=chat user=replicator",
          "source_publication",
          "my_subscription",
          enabled: false
        )

      assert :ok = result
      assert_received {:repo_query, _exists_sql}
      assert_received {:repo_query, create_sql}
      assert create_sql =~ "enabled = false"
    end

    test "creates subscription with both options" do
      result =
        LogicalReplicator.create_subscription(
          RepoMock,
          "host=localhost port=5432 dbname=chat user=replicator",
          "source_publication",
          "my_subscription",
          copy_data: true,
          enabled: false
        )

      assert :ok = result
      assert_received {:repo_query, _exists_sql}
      assert_received {:repo_query, create_sql}
      assert create_sql =~ "copy_data = true"
      assert create_sql =~ "enabled = false"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      result =
        LogicalReplicator.create_subscription(
          RepoMock,
          "host=localhost port=5432 dbname=chat user=replicator",
          "source_publication",
          "my_subscription"
        )

      assert {:error, :query_failed} = result
    end

    test "checks for existing subscription before creating" do
      LogicalReplicator.create_subscription(
        RepoMock,
        "host=localhost port=5432 dbname=chat user=replicator",
        "source_publication",
        "my_subscription"
      )

      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      assert exists_sql =~ "subname = 'my_subscription'"

      assert_received {:repo_query, create_sql}
      assert create_sql =~ "CREATE SUBSCRIPTION my_subscription"
    end
  end

  describe "enable_subscription/2" do
    test "enables subscription" do
      result =
        LogicalReplicator.enable_subscription(
          RepoMock,
          "my_subscription"
        )

      assert :ok = result
      assert_received {:repo_query, sql}
      assert sql =~ "ALTER SUBSCRIPTION my_subscription ENABLE"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      result =
        LogicalReplicator.enable_subscription(
          RepoMock,
          "my_subscription"
        )

      assert {:error, :query_failed} = result
    end
  end

  describe "disable_subscription/2" do
    test "disables subscription" do
      result =
        LogicalReplicator.disable_subscription(
          RepoMock,
          "my_subscription"
        )

      assert :ok = result
      assert_received {:repo_query, sql}
      assert sql =~ "ALTER SUBSCRIPTION my_subscription DISABLE"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      result =
        LogicalReplicator.disable_subscription(
          RepoMock,
          "my_subscription"
        )

      assert {:error, :query_failed} = result
    end
  end

  describe "disable_subscription_if_exists/2" do
    test "disables an existing subscription" do
      Process.put(:query_results, [
        {:ok, %{rows: [[1]], num_rows: 1}},
        :ok
      ])

      result =
        LogicalReplicator.disable_subscription_if_exists(
          RepoMock,
          "my_subscription"
        )

      assert :ok = result
      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      assert exists_sql =~ "subname = 'my_subscription'"
      assert_received {:repo_query, disable_sql}
      assert disable_sql =~ "ALTER SUBSCRIPTION my_subscription DISABLE"
    end

    test "is a no-op when the subscription does not exist" do
      Process.put(:query_results, [
        {:ok, %{rows: [], num_rows: 0}}
      ])

      result =
        LogicalReplicator.disable_subscription_if_exists(
          RepoMock,
          "my_subscription"
        )

      assert :ok = result
      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      refute_received {:repo_query, _disable_sql}
    end

    test "returns error when checking existing subscription fails" do
      Process.put(:query_results, [{:error, :query_failed}])

      result =
        LogicalReplicator.disable_subscription_if_exists(
          RepoMock,
          "my_subscription"
        )

      assert {:error, :query_failed} = result
    end
  end

  describe "check_replication_lag/2" do
    test "returns lag in bytes when subscription exists" do
      Process.put(:query_result, {:lag, 1024})

      result =
        LogicalReplicator.check_replication_lag(
          RepoMock,
          "my_subscription"
        )

      assert {:ok, 1024} = result
      assert_received {:repo_query, sql}
      assert sql =~ "pg_stat_subscription"
      assert sql =~ "subname = 'my_subscription'"
      assert sql =~ "pg_wal_lsn_diff(latest_end_lsn, received_lsn)"
    end

    test "returns zero lag when no lag" do
      Process.put(:query_result, {:lag, 0})

      result =
        LogicalReplicator.check_replication_lag(
          RepoMock,
          "my_subscription"
        )

      assert {:ok, 0} = result
    end

    test "returns error when subscription not found" do
      Process.put(:query_result, :subscription_not_found)

      result =
        LogicalReplicator.check_replication_lag(
          RepoMock,
          "my_subscription"
        )

      assert {:error, :subscription_not_found} = result
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      result =
        LogicalReplicator.check_replication_lag(
          RepoMock,
          "my_subscription"
        )

      assert {:error, :query_failed} = result
    end

    test "uses pg_wal_lsn_diff with latest_end_lsn and received_lsn" do
      Process.put(:query_result, {:lag, 2048})

      LogicalReplicator.check_replication_lag(
        RepoMock,
        "my_subscription"
      )

      assert_received {:repo_query, sql}
      assert sql =~ "pg_wal_lsn_diff(latest_end_lsn, received_lsn)"
      assert sql =~ "COALESCE"
    end

    test "truncates float lag to integer" do
      Process.put(:query_result, {:lag, 1024.5})

      result =
        LogicalReplicator.check_replication_lag(
          RepoMock,
          "my_subscription"
        )

      assert {:ok, 1024} = result
    end
  end
end
