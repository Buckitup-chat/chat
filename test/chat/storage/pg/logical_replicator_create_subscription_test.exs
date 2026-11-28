defmodule Chat.Storage.Pg.LogicalReplicatorCreateSubscriptionTest do
  use ExUnit.Case, async: true

  import ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock, only: [reset_repo_mock: 1]

  alias Chat.Storage.Pg.LogicalReplicator
  alias ChatSupport.Mocks.Storage.Pg.LogicalReplicatorRepoMock, as: RepoMock

  @moduletag :capture_log

  @conninfo "host=localhost port=5432 dbname=chat user=replicator"

  setup :reset_repo_mock

  describe "create_subscription/5" do
    test "creates subscription with default options" do
      conninfo = "host=localhost port=5432 dbname=chat user=replicator password=secret"

      assert :ok =
               LogicalReplicator.create_subscription(
                 RepoMock,
                 conninfo,
                 "source_publication",
                 "my_subscription"
               )

      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      assert exists_sql =~ "subname = 'my_subscription'"

      assert_received {:repo_query, create_sql}
      assert create_sql =~ "CREATE SUBSCRIPTION my_subscription"
      assert create_sql =~ "CONNECTION '#{conninfo}'"
      assert create_sql =~ "PUBLICATION source_publication"
      assert create_sql =~ "copy_data = false"
      assert create_sql =~ "enabled = true"
    end

    test "creates subscription with copy_data enabled" do
      assert :ok = create_subscription(copy_data: true)
      assert_received {:repo_query, _exists_sql}
      assert_received {:repo_query, create_sql}
      assert create_sql =~ "copy_data = true"
    end

    test "creates subscription with enabled false" do
      assert :ok = create_subscription(enabled: false)
      assert_received {:repo_query, _exists_sql}
      assert_received {:repo_query, create_sql}
      assert create_sql =~ "enabled = false"
    end

    test "creates subscription with both options" do
      assert :ok = create_subscription(copy_data: true, enabled: false)
      assert_received {:repo_query, _exists_sql}
      assert_received {:repo_query, create_sql}
      assert create_sql =~ "copy_data = true"
      assert create_sql =~ "enabled = false"
    end

    test "returns error when query fails" do
      Process.put(:query_result, :error)

      assert {:error, :query_failed} = create_subscription()
    end

    test "checks for existing subscription before creating" do
      create_subscription()

      assert_received {:repo_query, exists_sql}
      assert exists_sql =~ "FROM pg_subscription"
      assert exists_sql =~ "subname = 'my_subscription'"

      assert_received {:repo_query, create_sql}
      assert create_sql =~ "CREATE SUBSCRIPTION my_subscription"
    end
  end

  defp create_subscription(opts \\ []) do
    LogicalReplicator.create_subscription(
      RepoMock,
      @conninfo,
      "source_publication",
      "my_subscription",
      opts
    )
  end
end
