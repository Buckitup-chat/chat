defmodule Chat.Storage.Pg.LogicalReplicatorSlotsTest do
  use ExUnit.Case, async: true

  alias Chat.Storage.Pg.LogicalReplicator

  @moduletag :capture_log

  @found {:ok, %{rows: [[1]], num_rows: 1}}
  @none {:ok, %{rows: [], num_rows: 0}}
  @done {:ok, %{rows: [[""]], num_rows: 1}}

  # Answers scripted queries one per call; the walsender kill (query/2) always succeeds
  defmodule ScriptedRepo do
    def query(sql) do
      send(self(), {:query, sql})
      [result | rest] = Process.get(:script)
      Process.put(:script, rest)
      result
    end

    def query(sql, _params) do
      send(self(), {:terminate, sql})
      {:ok, %{rows: [], num_rows: 0}}
    end
  end

  describe "release_slot/3" do
    test "retries a busy slot until it drops" do
      script([@found, {:error, :slot_active}, @found, @done])

      assert :ok = LogicalReplicator.release_slot(ScriptedRepo, "slot", 2)
      assert 2 == count(:terminate)
    end

    test "gives up after the last attempt" do
      script([@found, {:error, :slot_active}, @found, {:error, :slot_active}])

      assert {:error, :slot_active} = LogicalReplicator.release_slot(ScriptedRepo, "slot", 2)
    end
  end

  describe "drop_slot_if_exists/2" do
    test "returns the error when the slot check fails" do
      script([{:error, :check_failed}])

      assert {:error, :check_failed} = LogicalReplicator.drop_slot_if_exists(ScriptedRepo, "slot")
    end
  end

  describe "ensure_slot_on_source/2" do
    test "returns the error when creating the slot fails" do
      script([@none, {:error, :create_failed}])

      assert {:error, :create_failed} =
               LogicalReplicator.ensure_slot_on_source(ScriptedRepo, "slot")

      assert 2 == count(:query)
    end

    test "returns the error when the slot check fails" do
      script([{:error, :check_failed}])

      assert {:error, :check_failed} =
               LogicalReplicator.ensure_slot_on_source(ScriptedRepo, "slot")

      assert 1 == count(:query)
    end
  end

  describe "check_replication_lag/2" do
    test "converts a Decimal lag to an integer" do
      script([{:ok, %{rows: [[Decimal.new(4096)]], num_rows: 1}}])

      assert {:ok, 4096} = LogicalReplicator.check_replication_lag(ScriptedRepo, "sub")
    end
  end

  # Helpers

  defp script(results), do: Process.put(:script, results)

  defp count(tag, acc \\ 0) do
    receive do
      {^tag, _sql} -> count(tag, acc + 1)
    after
      0 -> acc
    end
  end
end
