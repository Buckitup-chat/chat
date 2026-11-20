defmodule Chat.Storage.Pg.LogicalReplicatorIntegrationTest do
  use Chat.Test.PgPairCase, mode: :committed, async: false

  alias Chat.Storage.Pg
  alias Chat.Storage.Pg.LogicalReplicator
  alias Chat.Test.PgPairHelper.Db

  @moduletag :capture_log

  @names from(u in "users", select: u.name)

  describe "publications" do
    test "create_publication/3 creates and then updates a publication" do
      assert :ok = LogicalReplicator.create_publication(UnitARepo, ["users"], "internal_to_main")
      assert ["users"] = publication_tables(UnitARepo, "internal_to_main")

      assert :ok =
               LogicalReplicator.create_publication(
                 UnitARepo,
                 ["users", "user_cards"],
                 "internal_to_main"
               )

      assert ["user_cards", "users"] = publication_tables(UnitARepo, "internal_to_main")
    end

    test "publications in both directions coexist" do
      assert :ok = LogicalReplicator.create_publication(UnitARepo, ["users"], "internal_to_main")
      assert :ok = LogicalReplicator.create_publication(UnitBRepo, ["users"], "main_to_internal")

      assert ["users"] = publication_tables(UnitARepo, "internal_to_main")
      assert ["users"] = publication_tables(UnitBRepo, "main_to_internal")
    end
  end

  describe "slots" do
    test "ensure_slot_on_source/2 is idempotent and drop_slot_if_exists/2 removes it" do
      assert :ok = LogicalReplicator.ensure_slot_on_source(UnitARepo, "pg_pair_slot")
      assert :ok = LogicalReplicator.ensure_slot_on_source(UnitARepo, "pg_pair_slot")
      assert slot_exists?("pg_pair_slot")

      assert :ok = LogicalReplicator.drop_slot_if_exists(UnitARepo, "pg_pair_slot")
      refute slot_exists?("pg_pair_slot")
      assert :ok = LogicalReplicator.drop_slot_if_exists(UnitARepo, "pg_pair_slot")
    end
  end

  describe "subscriptions" do
    test "replicates rows A → B through the platform's copier flow" do
      replicate_a_to_b()

      UnitARepo.insert_all("users", [%{pub_key: <<7, 7, 7>>, name: "streamed"}])

      assert ["streamed"] = await_replicated(UnitBRepo, @names)
      assert {:ok, lag} = LogicalReplicator.check_replication_lag(UnitBRepo, "main_from_internal")
      assert lag >= 0
    end

    test "disabled subscription stops streaming; enabling resumes it" do
      replicate_a_to_b()

      assert :ok = LogicalReplicator.disable_subscription(UnitBRepo, "main_from_internal")
      UnitARepo.insert_all("users", [%{pub_key: <<8, 8, 8>>, name: "held"}])
      Process.sleep(300)
      assert [] = UnitBRepo.all(@names)

      assert :ok = LogicalReplicator.enable_subscription(UnitBRepo, "main_from_internal")
      assert ["held"] = await_replicated(UnitBRepo, @names)
    end

    test "drop_subscription_if_exists/2 drops it and keeps the source slot" do
      replicate_a_to_b()

      assert :ok = LogicalReplicator.drop_subscription_if_exists(UnitBRepo, "main_from_internal")
      assert [] = Db.rows(UnitBRepo, "SELECT subname FROM pg_subscription")
      assert slot_exists?("main_from_internal")

      assert :ok = LogicalReplicator.drop_subscription_if_exists(UnitBRepo, "main_from_internal")

      assert :ok =
               LogicalReplicator.disable_subscription_if_exists(UnitBRepo, "main_from_internal")
    end

    test "check_replication_lag/2 reports a missing subscription" do
      assert {:error, :subscription_not_found} =
               LogicalReplicator.check_replication_lag(UnitBRepo, "nope")
    end
  end

  describe "Chat.Storage.Pg" do
    test "system_identifier/1 returns the cluster id as a string" do
      assert Pg.system_identifier(UnitARepo) == to_string(system_id(UnitARepo))
      assert Pg.system_identifier(nil) == nil
    end

    test "build_connection_string/2 honours a port override" do
      conn = Pg.build_connection_string(UnitARepo, port: 6543)

      assert conn =~ "dbname=#{UnitARepo.config()[:database]}"
      assert conn =~ "port=6543"
    end
  end

  # Mirrors `Platform.Storage.InternalToMain.Copier`: slot first, then the subscription.
  # The slot already exists, so `create_subscription/5` takes its `create_slot = false` path,
  # which is also what keeps a same-cluster subscription from hanging.
  defp replicate_a_to_b do
    assert :ok = LogicalReplicator.create_publication(UnitARepo, ["users"], "internal_to_main")
    assert :ok = LogicalReplicator.ensure_slot_on_source(UnitARepo, "main_from_internal")

    assert :ok =
             LogicalReplicator.create_subscription(
               UnitBRepo,
               Pg.build_connection_string(UnitARepo),
               "internal_to_main",
               "main_from_internal"
             )
  end

  defp publication_tables(repo, name) do
    repo
    |> Db.rows("SELECT tablename FROM pg_publication_tables WHERE pubname = $1 ORDER BY 1", [name])
    |> List.flatten()
  end

  defp slot_exists?(name) do
    UnitARepo
    |> Db.rows("SELECT 1 FROM pg_replication_slots WHERE slot_name = $1", [name])
    |> Enum.any?()
  end
end
