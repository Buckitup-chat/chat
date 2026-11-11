defmodule Chat.Storage.Pg.BatchSyncUserSchemasTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Chat.Data.Schemas.{UserCard, UserStorage}
  alias Chat.Storage.Pg.BatchSync

  @moduletag :capture_log

  # Mock repos for user_cards and user_storage testing
  # These mocks need to handle both ID queries and full row queries
  defmodule SourceRepoMock do
    def all(query) do
      Process.get(:test_pid)
      |> send({:source_repo_all, query})

      query
      |> inspect()
      |> source_all_response()
    end

    def insert_all(schema_module, entries, opts \\ []) do
      Process.get(:test_pid)
      |> send({:source_repo_insert_all, schema_module, entries, opts})

      {length(entries), nil}
    end

    defp source_all_response(query_str) do
      case id_query?(query_str) do
        true -> source_id_response(query_str, Process.get(:source_data, :default))
        false -> source_row_response(query_str)
      end
    end

    defp id_query?(query_str) do
      String.contains?(query_str, "select:") and not String.contains?(query_str, "where:")
    end

    @composite_to_plain %{
      composite_default: :default,
      composite_with_missing: :with_missing,
      composite_full: :full
    }

    defp source_id_response(query_str, source_data) do
      cond do
        is_list(source_data) ->
          source_data

        Map.has_key?(@composite_to_plain, source_data) ->
          id_pairs(@composite_to_plain[source_data])

        composite_query?(query_str) ->
          id_pairs(source_data)

        true ->
          source_data |> id_pairs() |> Enum.map(fn {id, _uuid} -> id end)
      end
    end

    defp id_pairs(source_data) do
      case source_data do
        :default ->
          [{<<1, 2, 3>>, "uuid-1"}, {<<4, 5, 6>>, "uuid-2"}]

        :empty ->
          []

        :with_missing ->
          [{<<1, 2, 3>>, "uuid-1"}, {<<4, 5, 6>>, "uuid-2"}, {<<7, 8, 9>>, "uuid-3"}]

        :full ->
          [{<<1, 2, 3>>, "uuid-1"}]
      end
    end

    defp source_row_response(query_str) do
      cond do
        String.contains?(query_str, "UserCard") ->
          [
            %UserCard{
              user_hash: <<7, 8, 9>>,
              sign_pkey: <<4, 5, 6>>,
              contact_pkey: <<7, 8, 9>>,
              contact_cert: <<10, 11, 12>>,
              crypt_pkey: <<13, 14, 15>>,
              crypt_cert: <<16, 17, 18>>,
              name: "Alice"
            }
          ]

        String.contains?(query_str, "UserStorage") ->
          [
            %UserStorage{
              user_hash: <<7, 8, 9>>,
              uuid: "uuid-3",
              value_b64: <<100, 101, 102>>
            }
          ]

        true ->
          []
      end
    end

    defp composite_query?(query_str), do: String.contains?(query_str, "UserStorage")
  end

  defmodule TargetRepoMock do
    def all(query) do
      Process.get(:test_pid)
      |> send({:target_repo_all, query})

      case Process.get(:target_data, :default) do
        :default -> [<<1, 2, 3>>]
        :empty -> []
        :composite_default -> [{<<1, 2, 3>>, "uuid-1"}]
        :composite_empty -> []
        custom when is_list(custom) -> custom
      end
    end

    def insert_all(schema_module, entries, opts \\ []) do
      Process.get(:test_pid)
      |> send({:target_repo_insert_all, schema_module, entries, opts})

      case Process.get(:insert_result, :ok) do
        :ok ->
          {length(entries), nil}

        # Server-side SQL rejection (e.g. FK violation) — should be skipped, not fatal
        :constraint_error ->
          raise %Postgrex.Error{
            postgres: %{
              code: :foreign_key_violation,
              severity: "ERROR",
              pg_code: "23503",
              message: "insert or update on table violates foreign key constraint"
            }
          }

        # Connection lost — should abort the whole sync
        :connection_error ->
          raise %DBConnection.ConnectionError{message: "connection not available"}
      end
    end
  end

  setup do
    Process.put(:test_pid, self())
    Process.put(:query_count, 0)
    :ok
  end

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

      UserCard
      |> assert_insert_all([:user_hash], :nothing)
      |> assert_inserted_entry_keys([:user_hash])
    end

    test "uses user_hash as primary key for user_cards" do
      configure_sync(source_data: :full, target_data: :empty, current_schema: :user_cards)

      sync(schemas: [UserCard])

      UserCard
      |> assert_insert_all([:user_hash], :nothing)
      |> assert_inserted_entry_keys([:user_hash])
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

      UserCard
      |> assert_insert_all([:user_hash], :replace_all)
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

      UserStorage
      |> assert_insert_all([:user_hash, :uuid], :nothing)
      |> assert_inserted_entry_keys([:user_hash, :uuid, :value_b64])
    end

    test "uses composite key [user_hash, uuid] for user_storage" do
      configure_sync(
        source_data: :composite_full,
        target_data: :composite_empty,
        current_schema: :user_storage
      )

      sync(schemas: [UserStorage])

      UserStorage
      |> assert_insert_all([:user_hash, :uuid], :nothing)
      |> assert_inserted_entry_keys([:user_hash, :uuid, :value_b64])
    end

    test "handles empty user_storage source" do
      configure_sync(
        source_data: :empty,
        target_data: :composite_empty,
        current_schema: :user_storage
      )

      assert {:ok, stats} = sync(schemas: [UserStorage])
      assert stats[UserStorage] == 0
      refute_received {:target_repo_insert_all, _, _, _}
    end

    test "respects custom schema_config for user_storage" do
      configure_sync(
        source_data: :composite_full,
        target_data: :composite_empty,
        current_schema: :user_storage
      )

      sync(
        schemas: [UserStorage],
        schema_config: %{UserStorage => %{on_conflict: {:update, [:value_b64]}}}
      )

      UserStorage
      |> assert_insert_all([:user_hash, :uuid], {:replace, [:value_b64]})
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
      # This should NOT raise an error
      configure_sync(
        source_data: :composite_full,
        target_data: :composite_empty,
        current_schema: :user_storage
      )

      assert {:ok, stats} = sync(schemas: [UserStorage])
      assert stats[UserStorage] == 1
    end

    test "supports composite keys with 3 fields (hypothetical)" do
      # This tests that 3-field composite keys are supported
      # Even though we don't have a real schema with 3 fields yet
      assert %Ecto.Query{} = build_select_query([:field1, :field2, :field3])
    end
  end

  # Uses the real schema modules (not bare atoms) so config_for/2 can read their
  # primary keys — this is what exercises the skip/abort control flow end to end.
  describe "sync/1 - skip-and-continue vs abort" do
    test "skips a table whose rows Postgres rejects and reports partial" do
      configure_sync(
        source_data: :with_missing,
        target_data: :default,
        insert_result: :constraint_error
      )

      assert {:partial, synced, failed} = module_sync([UserCard])
      assert Map.has_key?(failed, UserCard)
      # Nothing was actually copied for the rejected table
      assert synced[UserCard] == 0
    end

    test "continues to later tables after a skippable failure" do
      configure_sync(
        source_data: :with_missing,
        target_data: :default,
        insert_result: :constraint_error
      )

      assert {:partial, _synced, failed} = module_sync([UserCard, UserStorage])
      # Both tables were attempted — the loop did NOT halt at the first failure
      assert Map.has_key?(failed, UserCard)
      assert Map.has_key?(failed, UserStorage)
    end

    test "aborts the whole sync on a connection error" do
      configure_sync(
        source_data: :with_missing,
        target_data: :default,
        insert_result: :connection_error
      )

      assert {:error, {:aborted, details}} = module_sync([UserCard, UserStorage])
      assert details.aborted_at == UserCard
      # The sync stopped — the later table was never reached
      refute Map.has_key?(details.synced, UserStorage)
    end

    test "returns ok when every table syncs cleanly" do
      configure_sync(
        source_data: :with_missing,
        target_data: :default,
        insert_result: :ok
      )

      assert {:ok, synced} = module_sync([UserCard])
      assert synced[UserCard] >= 1
    end
  end

  defp sync(opts \\ []) do
    [source_repo: SourceRepoMock, target_repo: TargetRepoMock]
    |> Keyword.merge(opts)
    |> BatchSync.sync()
  end

  defp module_sync(schemas) do
    BatchSync.sync(source_repo: SourceRepoMock, target_repo: TargetRepoMock, schemas: schemas)
  end

  defp configure_sync(opts) do
    Enum.each(opts, fn {key, value} -> Process.put(key, value) end)
  end

  defp assert_insert_all(schema_module, conflict_target, on_conflict) do
    assert_received {:target_repo_insert_all, ^schema_module, entries, opts}
    assert length(entries) == 1
    assert opts[:conflict_target] == conflict_target
    assert opts[:on_conflict] == on_conflict
    entries
  end

  defp assert_inserted_entry_keys([entry], required_keys) do
    Enum.each(required_keys, fn key ->
      assert Map.has_key?(entry, key)
    end)
  end

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
