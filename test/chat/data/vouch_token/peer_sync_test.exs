defmodule Chat.Data.VouchToken.PeerSyncTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  @vouch_kind "device.BK-001.storage.write"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    issuer = User.generate_pq_identity("Issuer")
    issuer_hash = insert_signed_user_card(issuer).user_hash
    subject_hash = insert_signed_user_card(User.generate_pq_identity("Subject")).user_hash
    {:ok, issuer: issuer, issuer_hash: issuer_hash, subject_hash: subject_hash}
  end

  describe "older vouch replayed by a peer snapshot" do
    test "does not undo a newer revocation", %{issuer: issuer} = ctx do
      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 200, true))
      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 100, false))

      assert %{deleted_flag: true, owner_timestamp: 200} = stored_vouch(ctx)
      assert :unreachable = chain_distance(ctx)
    end

    test "a newer revocation replaces an older grant", %{issuer: issuer} = ctx do
      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 100, false))
      assert {:ok, 1} = chain_distance(ctx)

      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 200, true))

      assert %{deleted_flag: true, owner_timestamp: 200} = stored_vouch(ctx)
      assert :unreachable = chain_distance(ctx)
    end

    test "on an equal timestamp the revocation wins, in either order", %{issuer: issuer} = ctx do
      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 300, false))
      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 300, true))
      assert %{deleted_flag: true, owner_timestamp: 300} = stored_vouch(ctx)

      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, signed_vouch(issuer, ctx, 300, false))
      assert %{deleted_flag: true, owner_timestamp: 300} = stored_vouch(ctx)
      assert :unreachable = chain_distance(ctx)
    end
  end

  defp signed_vouch(issuer, %{issuer_hash: issuer_hash, subject_hash: subject_hash}, ts, deleted) do
    %VouchToken{
      kind: @vouch_kind,
      issuer_hash: issuer_hash,
      subject_hash: subject_hash,
      owner_timestamp: ts,
      deleted_flag: deleted
    }
    |> sign_with_key(issuer.sign_skey)
  end

  defp stored_vouch(%{issuer_hash: issuer_hash, subject_hash: subject_hash}),
    do: VouchTokenData.get_vouch_token(@vouch_kind, issuer_hash, subject_hash)

  defp chain_distance(%{issuer_hash: issuer_hash, subject_hash: subject_hash}),
    do: VouchTokenData.chain_distance(issuer_hash, subject_hash, @vouch_kind)

  defp insert_signed_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_with_key(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end
end
