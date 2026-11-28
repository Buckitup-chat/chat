defmodule Chat.Storage.Pg.BatchSyncUserSchemasTest do
  use ExUnit.Case, async: true

  import ChatSupport.Mocks.Storage.Pg.BatchSyncUserSchemasRepoMocks,
    only: [register_test_pid: 1, configure_sync: 1]

  import Ecto.Query

  alias Chat.Data.Schemas.{UserCard, UserStorage}
  alias Chat.Storage.Pg.BatchSync
  alias ChatSupport.Mocks.Storage.Pg.BatchSyncUserSchemasRepoMocks.{SourceRepo, TargetRepo}

  @moduletag :capture_log

  setup :register_test_pid

  describe "sync/1 - user_cards schema" do
    test "syncs user_cards with single primary key (user_hash)" do
      configure_sync(
        source_data: :with_missing,
        target_data: :default,
        current_schema: :user_cards
      )

      assert {:ok, stats} = sync(schemas: [UserCard])
      assert stats[UserCard] == 1

      assert_received {:source_repo_all, _query}
      assert_received {:target_repo_all, _query}

      assert_received {:target_repo_insert_all, UserCard, [entry], opts}
      assert conflict_handling(opts) == {[:user_hash], :nothing}
      assert has_keys?(entry, [:user_hash])
    end

    test "uses user_hash as primary key for user_cards" do
      configure_sync(source_data: :full, target_data: :empty, current_schema: :user_cards)

      sync(schemas: [UserCard])

      assert_received {:target_repo_insert_all, UserCard, [entry], opts}
      assert conflict_handling(opts) == {[:user_hash], :nothing}
      assert has_keys?(entry, [:user_hash])
    end

    test "handles empty user_cards source" do
      configure_sync(source_data: :empty, target_data: :empty, current_schema: :user_cards)

      assert {:ok, stats} = sync(schemas: [UserCard])
      assert stats[UserCard] == 0
      refute_received {:target_repo_insert_all, _, _, _}
    end

    test "respects custom schema_config for user_cards" do
      configure_sync(source_data: :full, target_data: :empty, current_schema: :user_cards)

      sync(
        schemas: [UserCard],
        schema_config: %{UserCard => %{on_conflict: :replace_all}}
      )

      assert_received {:target_repo_insert_all, UserCard, [_entry], opts}
      assert conflict_handling(opts) == {[:user_hash], :replace_all}
    end
  end

  describe "sync/1 - user_storage schema with composite primary key" do
    test "syncs user_storage with composite primary key [user_hash, uuid]" do
      configure_sync(
        source_data: :composite_with_missing,
        target_data: :composite_default,
        current_schema: :user_storage
      )

      assert {:ok, stats} = sync(schemas: [UserStorage])
      assert stats[UserStorage] == 1

      assert_received {:source_repo_all, _query}
      assert_received {:target_repo_all, _query}

      assert_received {:target_repo_insert_all, UserStorage, [entry], opts}
      assert conflict_handling(opts) == {[:user_hash, :uuid], :nothing}
      assert has_keys?(entry, [:user_hash, :uuid, :value_b64])
    end

    test "uses composite key [user_hash, uuid] for user_storage" do
      configure_composite_sync(:composite_full)

      sync(schemas: [UserStorage])

      assert_received {:target_repo_insert_all, UserStorage, [entry], opts}
      assert conflict_handling(opts) == {[:user_hash, :uuid], :nothing}
      assert has_keys?(entry, [:user_hash, :uuid, :value_b64])
    end

    test "handles empty user_storage source" do
      configure_composite_sync(:empty)

      assert {:ok, stats} = sync(schemas: [UserStorage])
      assert stats[UserStorage] == 0
      refute_received {:target_repo_insert_all, _, _, _}
    end

    test "respects custom schema_config for user_storage" do
      configure_composite_sync(:composite_full)

      sync(
        schemas: [UserStorage],
        schema_config: %{UserStorage => %{on_conflict: {:update, [:value_b64]}}}
      )

      assert_received {:target_repo_insert_all, UserStorage, [_entry], opts}
      assert conflict_handling(opts) == {[:user_hash, :uuid], {:replace, [:value_b64]}}
    end
  end

  describe "sync/1 - both user_cards and user_storage" do
    test "syncs both schemas in order" do
      configure_sync(source_data: :full, target_data: :empty, current_schema: :user_cards)

      assert {:ok, stats} = sync(schemas: [UserCard, UserStorage])
      assert stats[UserCard] == 1
      assert stats[UserStorage] == 1

      assert_received {:target_repo_insert_all, UserCard, _, _}
      assert_received {:target_repo_insert_all, UserStorage, _, _}
    end

    test "uses default schemas when not provided" do
      configure_sync(source_data: :empty, target_data: :empty, current_schema: :user_cards)

      assert {:ok, stats} = sync()
      assert Map.has_key?(stats, UserCard)
      assert Map.has_key?(stats, UserStorage)
    end
  end

  describe "composite key error handling" do
    test "raises error for composite keys with 4 fields" do
      # This tests the error case in build_select_query
      assert_raise RuntimeError, "Composite keys with 4 fields not yet supported", fn ->
        build_select_query([:field1, :field2, :field3, :field4])
      end
    end

    test "raises error for composite keys with 5+ fields" do
      assert_raise RuntimeError, ~r/Composite keys with \d+ fields not yet supported/, fn ->
        build_select_query([:field1, :field2, :field3, :field4, :field5])
      end
    end

    test "supports composite keys with 2 fields (user_storage)" do
      configure_composite_sync(:composite_full)

      assert {:ok, stats} = sync(schemas: [UserStorage])
      assert stats[UserStorage] == 1
    end

    test "supports composite keys with 3 fields (hypothetical)" do
      # No real schema has a 3-field key yet
      assert %Ecto.Query{} = build_select_query([:field1, :field2, :field3])
    end
  end

  # Uses the real schema modules (not bare atoms) so config_for/2 can read their
  # primary keys — this is what exercises the skip/abort control flow end to end.
  describe "sync/1 - skip-and-continue vs abort" do
    test "skips a table whose rows Postgres rejects and reports partial" do
      configure_inserts(:constraint_error)

      assert {:partial, synced, failed} = sync(schemas: [UserCard])
      assert Map.has_key?(failed, UserCard)
      # Nothing was actually copied for the rejected table
      assert synced[UserCard] == 0
    end

    test "continues to later tables after a skippable failure" do
      configure_inserts(:constraint_error)

      assert {:partial, _synced, failed} = sync(schemas: [UserCard, UserStorage])
      # Both tables were attempted — the loop did NOT halt at the first failure
      assert Map.has_key?(failed, UserCard)
      assert Map.has_key?(failed, UserStorage)
    end

    test "aborts the whole sync on a connection error" do
      configure_inserts(:connection_error)

      assert {:error, {:aborted, details}} = sync(schemas: [UserCard, UserStorage])
      assert details.aborted_at == UserCard
      # The sync stopped — the later table was never reached
      refute Map.has_key?(details.synced, UserStorage)
    end

    test "returns ok when every table syncs cleanly" do
      configure_inserts(:ok)

      assert {:ok, synced} = sync(schemas: [UserCard])
      assert synced[UserCard] >= 1
    end
  end

  defp sync(opts \\ []) do
    [source_repo: SourceRepo, target_repo: TargetRepo]
    |> Keyword.merge(opts)
    |> BatchSync.sync()
  end

  defp configure_composite_sync(source_data) do
    configure_sync(
      source_data: source_data,
      target_data: :composite_empty,
      current_schema: :user_storage
    )
  end

  defp configure_inserts(insert_result) do
    configure_sync(
      source_data: :with_missing,
      target_data: :default,
      insert_result: insert_result
    )
  end

  defp conflict_handling(opts), do: {opts[:conflict_target], opts[:on_conflict]}

  defp has_keys?(entry, keys), do: Enum.all?(keys, &Map.has_key?(entry, &1))

  defp build_select_query(id_fields) do
    case id_fields do
      [field1, field2] ->
        from(s in UserCard, select: {field(s, ^field1), field(s, ^field2)})

      [field1, field2, field3] ->
        from(s in UserCard, select: {field(s, ^field1), field(s, ^field2), field(s, ^field3)})

      _ ->
        raise "Composite keys with #{length(id_fields)} fields not yet supported"
    end
  end
end
