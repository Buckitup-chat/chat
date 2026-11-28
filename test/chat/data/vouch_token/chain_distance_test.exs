defmodule Chat.Data.VouchToken.ChainDistanceTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.VouchChainFixtures

  @scope "device.BK-001.admin"

  setup :vouch_parties

  describe "basic traversal" do
    test "direct vouch yields distance 1", ctx do
      vouch(ctx, :owner, :alice, @scope)

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope)
    end

    test "transitive vouch yields distance 2", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :alice, :bob, @scope)

      assert {:ok, 2} = distance(ctx, :owner, :bob, @scope)
    end

    test "three-hop chain yields distance 3", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :alice, :bob, @scope)
      vouch(ctx, :bob, :carol, @scope)

      assert {:ok, 3} = distance(ctx, :owner, :carol, @scope)
    end

    test "unreachable user returns :unreachable", ctx do
      assert :unreachable = distance(ctx, :owner, :alice, @scope)
    end

    test "max_depth limits traversal", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :alice, :bob, @scope)

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope, 1)
      assert :unreachable = distance(ctx, :owner, :bob, @scope, 1)
    end

    test "sibling scope does not match", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.storage.write")

      assert :unreachable = distance(ctx, :owner, :alice, @scope)
    end

    test "wildcard device scope is walkable", ctx do
      wildcard = "device.*.admin"
      vouch(ctx, :owner, :alice, wildcard)
      vouch(ctx, :alice, :bob, wildcard)

      assert {:ok, 1} = distance(ctx, :owner, :alice, wildcard)
      assert {:ok, 2} = distance(ctx, :owner, :bob, wildcard)
    end

    test "broad wildcard vouch covers narrower specific scope", ctx do
      vouch(ctx, :owner, :alice, "device.*.storage")

      assert {:ok, 1} =
               distance(ctx, :owner, :alice, "device.BK-001.storage.write.user_card")
    end

    test "wildcard vouch is reachable via specific device scope", ctx do
      vouch(ctx, :owner, :alice, "device.*.storage.write.user_card")

      assert {:ok, 1} =
               distance(ctx, :owner, :alice, "device.BK-001.storage.write.user_card")
    end
  end

  describe "rule 1 — shortest chain wins" do
    test "direct path beats transitive path", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :owner, :bob, @scope)
      vouch(ctx, :alice, :bob, @scope)

      assert {:ok, 1} = distance(ctx, :owner, :bob, @scope)
    end

    test "two-hop beats three-hop", ctx do
      vouch(ctx, :owner, :alice, @scope)
      vouch(ctx, :alice, :carol, @scope)
      vouch(ctx, :owner, :bob, @scope)
      vouch(ctx, :bob, :carol, @scope)

      assert {:ok, 2} = distance(ctx, :owner, :carol, @scope)
    end
  end

  describe "rule 2 — wider scope wins" do
    test "parent scope vouch covers child scope check", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001")

      assert {:ok, 1} =
               distance(ctx, :owner, :alice, @scope)
    end

    test "grandparent scope vouch covers grandchild scope check", ctx do
      vouch(ctx, :owner, :alice, "device")

      assert {:ok, 1} =
               distance(ctx, :owner, :alice, @scope)
    end

    test "parent scope vouch is walkable transitively", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001")
      vouch(ctx, :alice, :bob, @scope)

      assert {:ok, 2} = distance(ctx, :owner, :bob, @scope)
    end

    test "child scope vouch found within subtree", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin.settings")

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope)
    end

    test "parent scope yields shorter distance than child scope path", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001")
      vouch(ctx, :owner, :bob, @scope)
      vouch(ctx, :bob, :alice, "device.BK-001.admin.settings")

      assert {:ok, 1} = distance(ctx, :owner, :alice, @scope)
    end
  end

  describe "scope must not widen down the chain" do
    test "wider grant is limited to parent's narrow scope", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin")
      vouch(ctx, :alice, :bob, "device")

      assert :unreachable = distance(ctx, :owner, :bob, "device")

      assert {:ok, 2} =
               distance(ctx, :owner, :bob, "device.BK-001.admin")
    end

    test "child link with same scope is reachable", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin")
      vouch(ctx, :alice, :bob, "device.BK-001.admin")

      assert {:ok, 2} =
               distance(ctx, :owner, :bob, "device.BK-001.admin")
    end

    test "child link narrowing scope is reachable", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001")
      vouch(ctx, :alice, :bob, "device.BK-001.admin")

      assert {:ok, 2} =
               distance(ctx, :owner, :bob, "device.BK-001.admin")
    end

    test "three-hop chain: widening at hop 3 is blocked", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin")
      vouch(ctx, :alice, :bob, "device.BK-001.admin.settings")
      # Bob tries to widen back — blocked by Alice's effective scope
      vouch(ctx, :bob, :carol, "device.BK-001")

      assert :unreachable =
               distance(ctx, :owner, :carol, "device.BK-001")

      assert {:ok, 3} =
               distance(ctx, :owner, :carol, "device.BK-001.admin.settings")
    end

    test "wildcard grant limited by parent's specific scope", ctx do
      vouch(ctx, :alice, :bob, "device.BK01.storage.read")
      vouch(ctx, :bob, :carol, "device.*.storage")

      assert {:ok, 2} =
               distance(ctx, :alice, :carol, "device.BK01.storage.read")

      assert :unreachable =
               distance(ctx, :alice, :carol, "device.*.storage")
    end

    test "alternative non-widening path still works when widening path exists", ctx do
      vouch(ctx, :owner, :alice, "device.BK-001.admin")
      vouch(ctx, :alice, :carol, "device")

      vouch(ctx, :owner, :bob, "device")
      vouch(ctx, :bob, :carol, "device")

      assert {:ok, 2} =
               distance(ctx, :owner, :carol, "device")
    end
  end
end
