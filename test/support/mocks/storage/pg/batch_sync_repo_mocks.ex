defmodule ChatSupport.Mocks.Storage.Pg.BatchSyncRepoMocks do
  @moduledoc """
  Source/target `Ecto.Repo` stand-ins for `Chat.Storage.Pg.BatchSync` unit tests
  over the `users` schema.

  Behaviour is driven by the test process dictionary: `:source_data`, `:target_data`
  and `:insert_result`. Every call is reported to `:test_pid`.
  """

  @doc "Named setup: resets the mock state and registers the test pid."
  def reset_repo_mocks(_context) do
    Process.put(:test_pid, self())
    Process.put(:source_data, :default)
    Process.put(:target_data, :default)
    Process.put(:insert_result, :ok)
    Process.put(:is_full_row_query, false)
    :ok
  end

  @doc "Sets what the source and target repos answer to ID queries."
  def given_repos(source_data, target_data) do
    Process.put(:source_data, source_data)
    Process.put(:target_data, target_data)
    :ok
  end

  defmodule OtherSchema do
    @moduledoc "Integer-keyed schema to exercise a second table in a sync."
    use Ecto.Schema

    @primary_key {:id, :integer, autogenerate: false}
    schema "other_table" do
      field(:name, :string)
    end
  end

  defmodule SourceRepo do
    @moduledoc false
    alias Chat.Test.PgPair.User

    def all(query) do
      send(Process.get(:test_pid), {:source_repo_all, query})

      source_data = Process.get(:source_data, :default)

      # Queries alternate: ID query first, then full row query for the missing IDs
      case Process.get(:is_full_row_query, false) do
        true ->
          Process.put(:is_full_row_query, false)
          full_row_response(source_data)

        false ->
          Process.put(:is_full_row_query, true)
          id_response(source_data)
      end
    end

    defp full_row_response(source_data) do
      case source_data do
        :full_users -> [%User{pub_key: "pk4", name: "user4"}]
        :empty -> []
        # pk3 is the missing one in default scenario
        _ -> [%User{pub_key: "pk3", name: "user3"}]
      end
    end

    defp id_response(source_data) do
      case source_data do
        :default -> ["pk1", "pk2", "pk3"]
        :empty -> []
        :with_missing -> ["pk1", "pk2", "pk3", "pk4"]
        :full_users -> ["pk4"]
        :same_as_source -> ["pk1", "pk2", "pk3"]
        custom when is_list(custom) -> custom
      end
    end
  end

  defmodule TargetRepo do
    @moduledoc false
    alias Chat.Test.PgPair.User

    def all(query) do
      send(Process.get(:test_pid), {:target_repo_all, query})

      case Process.get(:target_data, :default) do
        # target has pk1, pk2 (missing pk3)
        :default -> ["pk1", "pk2"]
        :empty -> []
        :same_as_source -> ["pk1", "pk2", "pk3"]
        custom when is_list(custom) -> custom
      end
    end

    def insert_all(schema_module, entries, opts \\ []) do
      send(Process.get(:test_pid), {:target_repo_insert_all, schema_module, entries, opts})

      case Process.get(:insert_result, :ok) do
        :ok -> {length(entries), nil}
        :error -> raise Postgrex.Error, message: "insert_all failed"
      end
    end

    def insert(changeset, opts \\ []) do
      send(Process.get(:test_pid), {:target_repo_insert, changeset, opts})

      case Process.get(:insert_result, :ok) do
        :ok -> {:ok, %User{pub_key: "inserted"}}
        :error -> {:error, :insert_failed}
      end
    end
  end
end
