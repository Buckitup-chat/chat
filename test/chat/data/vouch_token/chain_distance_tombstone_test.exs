defmodule Chat.Data.VouchToken.ChainDistanceTombstoneTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.VouchChainFixtures

  @scope "device.BK-001.admin"

  setup :vouch_parties

  describe "rule 3 — tombstone wins" do
    test "tombstoned edge breaks that chain", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :alice, :bob, @scope, deleted_flag: true)

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope)
      assert :unreachable = distance(ctx, :owner, :bob, @scope)
    end

    test "non-owner tombstone only kills that edge, alternative path works", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :owner, :bob, @scope)
      vouch(ctx, :alice, :carol, @scope, deleted_flag: true)
      vouch(ctx, :bob, :carol, @scope)

      assert {:ok, 2} = distance(ctx, :owner, :carol, @scope)
    end

    test "owner tombstone blocks subject even with alternative transitive path", ctx do
      vouch(ctx, :owner, :alice, @scope, deleted_flag: true)
      vouch(ctx, :owner, :bob, @scope)
      vouch(ctx, :bob, :alice, @scope)

      assert :unreachable = distance(ctx, :owner, :alice, @scope)
    end

    test "parent scope tombstone blocks child scope vouch", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin.settings")
      vouch(ctx, :owner, :alice, @scope, deleted_flag: true)

      assert :unreachable = distance(ctx, :owner, :alice, @scope)
    end

    test "parent scope tombstone blocks child scope in transitive chain", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :alice, :bob, "device.BK-001.admin.settings")
      vouch(ctx, :alice, :bob, @scope, deleted_flag: true)

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope)
      assert :unreachable = distance(ctx, :owner, :bob, @scope)
    end

    test "owner tombstone at parent scope blocks child scope access", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin.settings")
      vouch(ctx, :owner, :alice, "device.BK-001", deleted_flag: true)

      assert :unreachable =
               distance(ctx, :owner, :alice, @scope)
    end

    test "owner wildcard tombstone on transitive subject denies access", ctx do
      vouch(ctx, :alice, :bob, "device.bk01.storage.write")
      vouch(ctx, :bob, :carol, "device.bk01.storage.write")

      vouch(ctx, :alice, :carol, "device.*.storage", deleted_flag: true)

      assert {:ok, 1} =
               distance(ctx, :alice, :bob, "device.bk01.storage.write")

      assert :unreachable =
               distance(ctx, :alice, :carol, "device.bk01.storage.write")
    end

    test "child scope tombstone does not block parent scope vouch", ctx do
      vouch(ctx, :owner, :alice, @scope)

      vouch(ctx, :owner, :alice, "device.BK-001.admin.settings", deleted_flag: true)

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope)
    end
  end
end
