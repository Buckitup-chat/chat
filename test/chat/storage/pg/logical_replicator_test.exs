defmodule Chat.Storage.Pg.LogicalReplicatorTest do
  use ExUnit.Case, async: true

  import ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock, only: [reset_repo_mock: 1]

  alias Chat.Storage.Pg.LogicalReplicator
  alias ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock, as: RepoMock

  @moduletag :capture_log

  setup :reset_repo_mock

  describe "create_publication/3" do
    test "creates publication with specified tables" do
      result =
        LogicalReplicator.create_publication(RepoMock, ["users", "messages"], "my_publication")

      assert :ok = result
      assert_received {:repo_query, sql}
      assert sql =~ "CREATE PUBLICATION my_publication"
      assert sql =~ "FOR TABLE users, messages"
      assert sql =~ "IF NOT EXISTS"
    end

    test "creates publication with single table" do
      assert :ok = LogicalReplicator.create_publication(RepoMock, ["users"], "users_pub")
      assert_received {:repo_query, sql}
      assert sql =~ "FOR TABLE users"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      assert {:error, :query_failed} =
               LogicalReplicator.create_publication(RepoMock, ["users"], "my_publication")
    end

    test "uses DO $$ block for idempotency" do
      LogicalReplicator.create_publication(RepoMock, ["users"], "my_publication")

      assert_received {:repo_query, sql}
      assert sql =~ "DO $$"
      assert sql =~ "END $$"
    end
  end

  describe "enable_subscription/2" do
    test "enables subscription" do
      assert :ok = LogicalReplicator.enable_subscription(RepoMock, "my_subscription")
      assert_received {:repo_query, sql}
      assert sql =~ "ALTER SUBSCRIPTION my_subscription ENABLE"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      assert {:error, :query_failed} =
               LogicalReplicator.enable_subscription(RepoMock, "my_subscription")
    end
  end

  describe "disable_subscription/2" do
    test "disables subscription" do
      assert :ok = LogicalReplicator.disable_subscription(RepoMock, "my_subscription")
      assert_received {:repo_query, sql}
      assert sql =~ "ALTER SUBSCRIPTION my_subscription DISABLE"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      assert {:error, :query_failed} =
               LogicalReplicator.disable_subscription(RepoMock, "my_subscription")
    end
  end

  describe "disable_subscription_if_exists/2" do
    test "disables an existing subscription" do
      Process.put(:query_results, [{:ok, %{rows: [[1]], num_rows: 1}}, :ok])

      assert :ok = disable_if_exists()
      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      assert exists_sql =~ "subname = 'my_subscription'"
      assert_received {:repo_query, disable_sql}
      assert disable_sql =~ "ALTER SUBSCRIPTION my_subscription DISABLE"
    end

    test "is a no-op when the subscription does not exist" do
      Process.put(:query_results, [{:ok, %{rows: [], num_rows: 0}}])

      assert :ok = disable_if_exists()
      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      refute_received {:repo_query, _disable_sql}
    end

    test "returns error when checking existing subscription fails" do
      Process.put(:query_results, [{:error, :query_failed}])

      assert {:error, :query_failed} = disable_if_exists()
    end

    defp disable_if_exists,
      do: LogicalReplicator.disable_subscription_if_exists(RepoMock, "my_subscription")
  end
end
