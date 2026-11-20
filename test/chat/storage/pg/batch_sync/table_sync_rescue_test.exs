defmodule Chat.Storage.Pg.BatchSync.TableSyncRescueTest do
  use ExUnit.Case, async: true

  alias Chat.Storage.Pg.BatchSync.TableSync

  @moduletag :capture_log

  defmodule TestSchema do
    use Ecto.Schema

    @primary_key {:id, :integer, autogenerate: false}
    schema "test_table" do
      field(:name, :string)
    end
  end

  defmodule RaisingRepo do
    def all(_query) do
      raise Process.get(:raise_error)
    end
  end

  @config %{
    id_field: :id,
    conflict_target: [:id],
    on_conflict: :nothing
  }

  describe "sync_table/5 rescue clause" do
    test "returns {:partial, 0, error} for Postgrex.Error with postgres metadata" do
      error = %Postgrex.Error{
        message: "constraint violation",
        postgres: %{code: :unique_violation}
      }

      Process.put(:raise_error, error)

      assert {:partial, 0, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
               TableSync.sync_table(RaisingRepo, RaisingRepo, TestSchema, 100, @config)
    end

    test "returns {:abort, error} for Postgrex.Error without postgres metadata" do
      error = %Postgrex.Error{message: "connection refused", postgres: nil}
      Process.put(:raise_error, error)

      assert {:abort, %Postgrex.Error{message: "connection refused"}} =
               TableSync.sync_table(RaisingRepo, RaisingRepo, TestSchema, 100, @config)
    end

    test "returns {:abort, error} for non-Postgrex errors" do
      Process.put(:raise_error, %RuntimeError{message: "boom"})

      assert {:abort, %RuntimeError{message: "boom"}} =
               TableSync.sync_table(RaisingRepo, RaisingRepo, TestSchema, 100, @config)
    end
  end
end
