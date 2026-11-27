defmodule Chat.Storage.Pg.LogicalReplicator.SubscriptionTest do
  use ExUnit.Case, async: true

  alias Chat.Storage.Pg.LogicalReplicator.Subscription

  @moduletag :capture_log

  @conn "host=localhost port=5432 dbname=chat user=replicator"
  @found {:ok, %{rows: [[1]], num_rows: 1}}
  @none {:ok, %{rows: [], num_rows: 0}}
  @done {:ok, %{rows: [], num_rows: 0}}
  @slot_taken {:error,
               %Postgrex.Error{postgres: %{message: ~S(replication slot "sub" already exists)}}}

  # Answers queries from the script in the process dictionary, one per call
  defmodule ScriptedRepo do
    def query(sql) do
      send(self(), {:query, sql})
      [result | rest] = Process.get(:script)
      Process.put(:script, rest)
      result
    end
  end

  describe "create_subscription/4" do
    test "is a no-op when the subscription already exists" do
      script([@found])

      assert :ok = Subscription.create_subscription(ScriptedRepo, @conn, "pub", "sub")
      assert ["SELECT 1 FROM pg_subscription" <> _] = queries()
    end

    test "reuses the slot left on the source when it already exists" do
      script([@none, @slot_taken, @done, @done, @done])

      assert :ok = Subscription.create_subscription(ScriptedRepo, @conn, "pub", "sub")

      assert [_exists, _create, without_slot, set_slot, enable] = queries()
      assert without_slot =~ "create_slot = false"
      assert without_slot =~ "enabled = false"
      assert set_slot == "ALTER SUBSCRIPTION sub SET (slot_name = 'sub')"
      assert enable == "ALTER SUBSCRIPTION sub ENABLE"
    end

    test "leaves the reused-slot subscription disabled when asked" do
      script([@none, @slot_taken, @done, @done])

      assert :ok =
               Subscription.create_subscription(ScriptedRepo, @conn, "pub", "sub", enabled: false)

      assert [_exists, _create, _without_slot, _set_slot] = queries()
    end

    test "returns the error when creating without a slot fails" do
      script([@none, @slot_taken, @done, {:error, :set_slot_failed}])

      assert {:error, :set_slot_failed} =
               Subscription.create_subscription(ScriptedRepo, @conn, "pub", "sub")
    end

    test "returns a PostgreSQL error other than an existing slot" do
      denied = {:error, %Postgrex.Error{postgres: %{message: "permission denied"}}}
      script([@none, denied])

      assert ^denied = Subscription.create_subscription(ScriptedRepo, @conn, "pub", "sub")
      assert [_exists, _create] = queries()
    end

    test "returns a non-PostgreSQL create error" do
      script([@none, {:error, :closed}])

      assert {:error, :closed} =
               Subscription.create_subscription(ScriptedRepo, @conn, "pub", "sub")
    end
  end

  describe "drop_subscription_if_exists/2" do
    test "is a no-op when the subscription is absent" do
      script([@none])

      assert :ok = Subscription.drop_subscription_if_exists(ScriptedRepo, "sub")
      assert [_exists] = queries()
    end

    test "disables, detaches the slot and drops an existing subscription" do
      script([@found, @done, @done, @done])

      assert :ok = Subscription.drop_subscription_if_exists(ScriptedRepo, "sub")

      assert [
               _exists,
               "ALTER SUBSCRIPTION sub DISABLE",
               "ALTER SUBSCRIPTION sub SET (slot_name = NONE)",
               "DROP SUBSCRIPTION sub"
             ] = queries()
    end

    test "drops even when disabling and detaching fail" do
      script([@found, {:error, :disable_failed}, {:error, :detach_failed}, @done])

      assert :ok = Subscription.drop_subscription_if_exists(ScriptedRepo, "sub")
    end

    test "returns the error when the drop fails" do
      script([@found, @done, @done, {:error, :drop_failed}])

      assert {:error, :drop_failed} =
               Subscription.drop_subscription_if_exists(ScriptedRepo, "sub")
    end

    test "returns the error when the existence check fails" do
      script([{:error, :check_failed}])

      assert {:error, :check_failed} =
               Subscription.drop_subscription_if_exists(ScriptedRepo, "sub")

      assert [_exists] = queries()
    end
  end

  # Helpers

  defp script(results), do: Process.put(:script, results)

  defp queries(acc \\ []) do
    receive do
      {:query, sql} -> queries([String.trim(sql) | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
