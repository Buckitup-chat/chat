defmodule Chat.Data.VouchToken.ChainDistanceTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_key: 2]

  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData

  @scope "device.BK-001.admin"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    alice = User.generate_pq_identity("Alice")
    bob = User.generate_pq_identity("Bob")
    carol = User.generate_pq_identity("Carol")

    owner_card = insert_user_card(owner)
    alice_card = insert_user_card(alice)
    bob_card = insert_user_card(bob)
    carol_card = insert_user_card(carol)

    {:ok,
     owner: owner,
     alice: alice,
     bob: bob,
     carol: carol,
     owner_hash: owner_card.user_hash,
     alice_hash: alice_card.user_hash,
     bob_hash: bob_card.user_hash,
     carol_hash: carol_card.user_hash}
  end

  describe "basic traversal" do
    test "direct vouch yields distance 1", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "transitive vouch yields distance 2", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope)

      assert {:ok, 2} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, @scope)
    end

    test "three-hop chain yields distance 3", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope)
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, @scope)

      assert {:ok, 3} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.carol_hash, @scope)
    end

    test "unreachable user returns :unreachable", ctx do
      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "max_depth limits traversal", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope)

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope, 1)
      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, @scope, 1)
    end

    test "sibling scope does not match", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.storage.write")

      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "wildcard device scope is walkable", ctx do
      wildcard = "device.*.admin"
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, wildcard)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, wildcard)

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, wildcard)
      assert {:ok, 2} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, wildcard)
    end

    test "broad wildcard vouch covers narrower specific scope", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.*.storage")

      assert {:ok, 1} =
               VouchTokenData.chain_distance(
                 ctx.owner_hash,
                 ctx.alice_hash,
                 "device.BK-001.storage.write.user_card"
               )
    end

    test "wildcard vouch is reachable via specific device scope", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.*.storage.write.user_card")

      assert {:ok, 1} =
               VouchTokenData.chain_distance(
                 ctx.owner_hash,
                 ctx.alice_hash,
                 "device.BK-001.storage.write.user_card"
               )
    end
  end

  describe "rule 1 — shortest chain wins" do
    test "direct path beats transitive path", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.bob_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope)

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, @scope)
    end

    test "two-hop beats three-hop", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.carol_hash, @scope)
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.bob_hash, @scope)
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, @scope)

      assert {:ok, 2} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.carol_hash, @scope)
    end
  end

  describe "rule 2 — wider scope wins" do
    test "parent scope vouch covers child scope check", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001")

      assert {:ok, 1} =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "grandparent scope vouch covers grandchild scope check", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device")

      assert {:ok, 1} =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "parent scope vouch is walkable transitively", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope)

      assert {:ok, 2} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, @scope)
    end

    test "child scope vouch found within subtree", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin.settings")

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "parent scope yields shorter distance than child scope path", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001")
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.bob_hash, @scope)
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.alice_hash, "device.BK-001.admin.settings")

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end
  end

  describe "scope must not widen down the chain" do
    test "wider grant is limited to parent's narrow scope", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device")

      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, "device")

      assert {:ok, 2} =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, "device.BK-001.admin")
    end

    test "child link with same scope is reachable", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device.BK-001.admin")

      assert {:ok, 2} =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, "device.BK-001.admin")
    end

    test "child link narrowing scope is reachable", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device.BK-001.admin")

      assert {:ok, 2} =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, "device.BK-001.admin")
    end

    test "three-hop chain: widening at hop 3 is blocked", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device.BK-001.admin.settings")
      # Bob tries to widen back — blocked by Alice's effective scope
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, "device.BK-001")

      assert :unreachable =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.carol_hash, "device.BK-001")

      assert {:ok, 3} =
               VouchTokenData.chain_distance(
                 ctx.owner_hash,
                 ctx.carol_hash,
                 "device.BK-001.admin.settings"
               )
    end

    test "wildcard grant limited by parent's specific scope", ctx do
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device.BK01.storage.read")
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, "device.*.storage")

      assert {:ok, 2} =
               VouchTokenData.chain_distance(
                 ctx.alice_hash,
                 ctx.carol_hash,
                 "device.BK01.storage.read"
               )

      assert :unreachable =
               VouchTokenData.chain_distance(ctx.alice_hash, ctx.carol_hash, "device.*.storage")
    end

    test "alternative non-widening path still works when widening path exists", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.carol_hash, "device")

      insert_vouch(ctx.owner, ctx.owner_hash, ctx.bob_hash, "device")
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, "device")

      assert {:ok, 2} =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.carol_hash, "device")
    end
  end

  describe "rule 3 — tombstone wins" do
    test "tombstoned edge breaks that chain", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope, deleted_flag: true)

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, @scope)
    end

    test "non-owner tombstone only kills that edge, alternative path works", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.bob_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.carol_hash, @scope, deleted_flag: true)
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, @scope)

      assert {:ok, 2} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.carol_hash, @scope)
    end

    test "owner tombstone blocks subject even with alternative transitive path", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope, deleted_flag: true)
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.bob_hash, @scope)
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.alice_hash, @scope)

      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "parent scope tombstone blocks child scope vouch", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin.settings")
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope, deleted_flag: true)

      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "parent scope tombstone blocks child scope in transitive chain", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device.BK-001.admin.settings")
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, @scope, deleted_flag: true)

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
      assert :unreachable = VouchTokenData.chain_distance(ctx.owner_hash, ctx.bob_hash, @scope)
    end

    test "owner tombstone at parent scope blocks child scope access", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin.settings")
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001", deleted_flag: true)

      assert :unreachable =
               VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end

    test "owner wildcard tombstone on transitive subject denies access", ctx do
      insert_vouch(ctx.alice, ctx.alice_hash, ctx.bob_hash, "device.bk01.storage.write")
      insert_vouch(ctx.bob, ctx.bob_hash, ctx.carol_hash, "device.bk01.storage.write")

      insert_vouch(ctx.alice, ctx.alice_hash, ctx.carol_hash, "device.*.storage",
        deleted_flag: true
      )

      assert {:ok, 1} =
               VouchTokenData.chain_distance(
                 ctx.alice_hash,
                 ctx.bob_hash,
                 "device.bk01.storage.write"
               )

      assert :unreachable =
               VouchTokenData.chain_distance(
                 ctx.alice_hash,
                 ctx.carol_hash,
                 "device.bk01.storage.write"
               )
    end

    test "child scope tombstone does not block parent scope vouch", ctx do
      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, @scope)

      insert_vouch(ctx.owner, ctx.owner_hash, ctx.alice_hash, "device.BK-001.admin.settings",
        deleted_flag: true
      )

      assert {:ok, 1} = VouchTokenData.chain_distance(ctx.owner_hash, ctx.alice_hash, @scope)
    end
  end

  # Helpers

  defp insert_vouch(issuer_identity, issuer_hash, subject_hash, kind, opts \\ []) do
    vt =
      %VouchToken{
        kind: kind,
        issuer_hash: issuer_hash,
        subject_hash: subject_hash,
        owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond)),
        deleted_flag: Keyword.get(opts, :deleted_flag, false)
      }
      |> sign_with_key(issuer_identity.sign_skey)

    {:ok, _} =
      VouchTokenData.upsert_vouch_token(
        VouchToken.create_changeset(%VouchToken{}, Map.from_struct(vt))
      )
  end
end
