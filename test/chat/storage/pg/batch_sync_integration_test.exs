defmodule Chat.Storage.Pg.BatchSyncIntegrationTest do
  use Chat.Test.PgPairCase, mode: :sandbox, async: true

  alias Chat.Storage.Pg.BatchSync
  alias Chat.Test.PgPair.User

  @moduletag :capture_log

  describe "sync/1 - with real databases" do
    test "syncs missing rows from source to target" do
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk1", name: "Alice"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk2", name: "Bob"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk3", name: "Charlie"})

      assert UnitARepo.aggregate(User, :count) == 3

      assert UnitBRepo.aggregate(User, :count) == 0

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 3

      assert UnitBRepo.aggregate(User, :count) == 3

      users = UnitBRepo.all(User) |> Enum.sort_by(& &1.pub_key)
      assert length(users) == 3
      assert Enum.at(users, 0).name == "Alice"
      assert Enum.at(users, 1).name == "Bob"
      assert Enum.at(users, 2).name == "Charlie"
    end

    test "preserves existing rows on target (CRDT-like behavior)" do
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk1", name: "Alice"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk2", name: "Bob"})

      {:ok, _} = UnitBRepo.insert(%User{pub_key: "pk1", name: "Alice Original"})

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 1

      assert UnitBRepo.aggregate(User, :count) == 2

      user = UnitBRepo.get!(User, "pk1")
      assert user.name == "Alice Original"
    end

    test "handles empty source database" do
      {:ok, _} = UnitBRepo.insert(%User{pub_key: "pk1", name: "Alice"})

      assert UnitARepo.aggregate(User, :count) == 0

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 0

      assert UnitBRepo.aggregate(User, :count) == 1
    end

    test "handles empty target database" do
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk1", name: "Alice"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk2", name: "Bob"})

      assert UnitBRepo.aggregate(User, :count) == 0

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 2

      assert UnitBRepo.aggregate(User, :count) == 2
    end

    test "syncs in reverse direction (main to internal)" do
      {:ok, _} = UnitBRepo.insert(%User{pub_key: "pk1", name: "Alice"})
      {:ok, _} = UnitBRepo.insert(%User{pub_key: "pk2", name: "Bob"})

      assert UnitARepo.aggregate(User, :count) == 0

      result =
        BatchSync.sync(
          source_repo: UnitBRepo,
          target_repo: UnitARepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 2

      assert UnitARepo.aggregate(User, :count) == 2
    end

    test "handles partial sync (some rows already exist)" do
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk1", name: "Alice"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk2", name: "Bob"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk3", name: "Charlie"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk4", name: "David"})
      {:ok, _} = UnitARepo.insert(%User{pub_key: "pk5", name: "Eve"})

      {:ok, _} = UnitBRepo.insert(%User{pub_key: "pk1", name: "Alice"})
      {:ok, _} = UnitBRepo.insert(%User{pub_key: "pk3", name: "Charlie"})

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 3

      assert UnitBRepo.aggregate(User, :count) == 5
    end

    test "handles binary pub_key correctly" do
      binary_key = :crypto.strong_rand_bytes(32)
      {:ok, _} = UnitARepo.insert(%User{pub_key: binary_key, name: "Binary User"})

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert stats[User] == 1

      user = UnitBRepo.get!(User, binary_key)
      assert user.pub_key == binary_key
      assert user.name == "Binary User"
    end

    test "returns statistics for sync operation" do
      for i <- 1..10 do
        {:ok, _} = UnitARepo.insert(%User{pub_key: "pk#{i}", name: "User #{i}"})
      end

      result =
        BatchSync.sync(
          source_repo: UnitARepo,
          target_repo: UnitBRepo,
          schemas: [User]
        )

      assert {:ok, stats} = result
      assert is_map(stats)
      assert stats[User] == 10
    end
  end
end
