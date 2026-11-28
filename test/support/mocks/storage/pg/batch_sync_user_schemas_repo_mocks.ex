defmodule ChatSupport.Mocks.Storage.Pg.BatchSyncUserSchemasRepoMocks do
  @moduledoc """
  Source/target `Ecto.Repo` stand-ins for `Chat.Storage.Pg.BatchSync` tests over
  `user_cards` (single key) and `user_storage` (composite `[user_hash, uuid]` key).

  Both handle ID queries and full row queries. Behaviour is driven by the test process
  dictionary: `:source_data`, `:target_data` and `:insert_result`. Every call is
  reported to `:test_pid`.
  """

  @doc "Named setup: registers the test pid."
  def register_test_pid(_context) do
    Process.put(:test_pid, self())
    Process.put(:query_count, 0)
    :ok
  end

  @doc "Puts each `{key, value}` into the process dictionary the mocks read."
  def configure_sync(opts) do
    Enum.each(opts, fn {key, value} -> Process.put(key, value) end)
  end

  defmodule SourceRepo do
    @moduledoc false
    alias Chat.Data.Schemas.{UserCard, UserStorage}

    @composite_to_plain %{
      composite_default: :default,
      composite_with_missing: :with_missing,
      composite_full: :full
    }

    def all(query) do
      send(Process.get(:test_pid), {:source_repo_all, query})

      query
      |> inspect()
      |> source_all_response()
    end

    def insert_all(schema_module, entries, opts \\ []) do
      send(Process.get(:test_pid), {:source_repo_insert_all, schema_module, entries, opts})

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
          [%UserStorage{user_hash: <<7, 8, 9>>, uuid: "uuid-3", value_b64: <<100, 101, 102>>}]

        true ->
          []
      end
    end

    defp composite_query?(query_str), do: String.contains?(query_str, "UserStorage")
  end

  defmodule TargetRepo do
    @moduledoc false

    def all(query) do
      send(Process.get(:test_pid), {:target_repo_all, query})

      case Process.get(:target_data, :default) do
        :default -> [<<1, 2, 3>>]
        :empty -> []
        :composite_default -> [{<<1, 2, 3>>, "uuid-1"}]
        :composite_empty -> []
        custom when is_list(custom) -> custom
      end
    end

    def insert_all(schema_module, entries, opts \\ []) do
      send(Process.get(:test_pid), {:target_repo_insert_all, schema_module, entries, opts})

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
end
