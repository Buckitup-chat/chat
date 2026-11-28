defmodule Chat.Storage.Pg.BatchSyncConflictConfigTest do
  use ExUnit.Case, async: true

  import ChatSupport.Mocks.Storage.Pg.BatchSyncRepoMocks,
    only: [reset_repo_mocks: 1, given_repos: 2]

  alias Chat.Storage.Pg.BatchSync
  alias Chat.Test.PgPair.User
  alias ChatSupport.Mocks.Storage.Pg.BatchSyncRepoMocks.{OtherSchema, SourceRepo, TargetRepo}

  @moduletag :capture_log

  @repos [source_repo: SourceRepo, target_repo: TargetRepo]

  setup :reset_repo_mocks

  describe "sync/1 - configurable conflict resolution" do
    setup do
      given_repos(:full_users, :empty)
    end

    test "uses default :nothing conflict strategy when no config provided" do
      sync_users()

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:on_conflict] == :nothing
      assert opts[:conflict_target] == [:pub_key]
    end

    test "uses custom :nothing conflict strategy from schema_config" do
      sync_users_with_config(%{on_conflict: :nothing})

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:on_conflict] == :nothing
    end

    test "uses :replace_all conflict strategy from schema_config" do
      sync_users_with_config(%{on_conflict: :replace_all})

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:on_conflict] == :replace_all
    end

    test "uses {:update, fields} conflict strategy from schema_config" do
      sync_users_with_config(%{on_conflict: {:update, [:name, :updated_at]}})

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:on_conflict] == {:replace, [:name, :updated_at]}
    end

    test "uses custom conflict_target from schema_config" do
      sync_users_with_config(%{conflict_target: [:pub_key, :name]})

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:conflict_target] == [:pub_key, :name]
    end

    test "uses custom id_field from schema_config" do
      # id_field picks the field used for diffing; the default for users is :pub_key
      sync_users_with_config(%{id_field: :pub_key})

      assert_received {:source_repo_all, _query}
      assert_received {:target_repo_all, _query}
    end

    test "merges custom config with defaults" do
      # Only on_conflict is overridden; id_field and conflict_target keep their defaults
      sync_users_with_config(%{on_conflict: :replace_all})

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:on_conflict] == :replace_all
      assert opts[:conflict_target] == [:pub_key]
    end

    test "falls back to :nothing for unknown conflict strategies" do
      sync_users_with_config(%{on_conflict: :unknown_strategy})

      assert_received {:target_repo_insert_all, _schema, _entries, opts}
      assert opts[:on_conflict] == :nothing
    end

    test "derives conflict target from the schema primary key" do
      given_repos(:with_missing, :default)

      assert {:ok, _} = @repos |> Keyword.put(:schemas, [OtherSchema]) |> BatchSync.sync()

      assert_received {:target_repo_insert_all, OtherSchema, _entries, opts}
      assert opts[:conflict_target] == [:id]
    end
  end

  defp sync_users, do: @repos |> Keyword.put(:schemas, [User]) |> BatchSync.sync()

  defp sync_users_with_config(user_config) do
    BatchSync.sync(@repos ++ [schemas: [User], schema_config: %{User => user_config}])
  end
end
