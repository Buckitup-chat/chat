defmodule ChatWeb.ElectricControllerWriteGateTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Chat.Test.ElectricIngestHelpers, only: [post_signed: 4, to_base64: 1]
  import Chat.Test.ReadGateHelpers

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    {owner, owner_card} = identity_with_card("Owner")
    {bob, bob_card} = identity_with_card("Bob")
    put_gate(:guarded, owner_card)

    %{owner: owner, owner_card: owner_card, bob: bob, bob_card: bob_card}
  end

  describe "POST /electric/v1/ingest" do
    test "unvouched write is 403 JSON", ctx do
      conn = post_mutations(ctx.conn, "/ingest", [storage_insert(ctx.bob_card, ctx.bob)], ctx.bob)

      assert %{"error" => "not_in_trust_chain", "max_depth" => 7} = json_response(conn, 403)
    end

    test "vouched write passes", ctx do
      vouch(ctx.owner, ctx.owner_card.user_hash, ctx.bob_card.user_hash, "storage.write")

      conn = post_mutations(ctx.conn, "/ingest", [storage_insert(ctx.bob_card, ctx.bob)], ctx.bob)

      assert %{"txid" => _} = json_response(conn, 200)
    end
  end

  describe "POST /electric/v1/ingest_each" do
    test "all rows blocked is 403 with per-row errors", ctx do
      mutations = [storage_insert(ctx.bob_card, ctx.bob), storage_insert(ctx.bob_card, ctx.bob)]

      conn = post_mutations(ctx.conn, "/ingest_each", mutations, ctx.bob)

      assert %{"results" => [row, _]} = json_response(conn, 403)
      assert %{"status" => "error", "error" => "not_in_trust_chain", "max_depth" => 7} = row
    end

    test "blocked rows next to other errors keep 422", ctx do
      # owner's row under bob's PoP fails its own check before the gate
      mutations = [
        storage_insert(ctx.owner_card, ctx.owner),
        storage_insert(ctx.bob_card, ctx.bob)
      ]

      conn = post_mutations(ctx.conn, "/ingest_each", mutations, ctx.bob)

      assert %{"results" => [invalid, blocked]} = json_response(conn, 422)
      assert %{"error" => "Invalid operation"} = invalid
      assert %{"error" => "not_in_trust_chain", "max_depth" => 7} = blocked
    end
  end

  defp post_mutations(conn, path, mutations, identity) do
    post_signed(conn, "/electric/v1" <> path, %{"mutations" => mutations}, identity.sign_skey)
  end

  defp storage_insert(card, identity) do
    row = %UserStorage{
      user_hash: card.user_hash,
      uuid: Ecto.UUID.generate(),
      value_b64: "blob",
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: System.system_time(:second)
    }

    sign_b64 = row |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)

    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => row.user_hash,
        "uuid" => row.uuid,
        "value_b64" => to_base64(row.value_b64),
        "deleted_flag" => row.deleted_flag,
        "owner_timestamp" => row.owner_timestamp,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_b64 |> EnigmaPq.hash() |> UserStorageSignHash.from_binary()
      },
      "syncMetadata" => %{"relation" => "user_storage"}
    }
  end
end
