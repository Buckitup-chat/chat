defmodule Chat.Data.VouchToken.ValidationTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_key: 2]

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.User
  alias Chat.Data.VouchToken.Validation
  alias EnigmaPq

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    issuer = User.generate_pq_identity("Issuer")
    subject = User.generate_pq_identity("Subject")

    issuer_card = insert_user_card(issuer)
    subject_card = insert_user_card(subject)

    {:ok,
     issuer: issuer,
     subject: subject,
     issuer_hash: issuer_card.user_hash,
     subject_hash: subject_card.user_hash}
  end

  describe "validate_vouch_token_insert/1" do
    test "accepts a validly signed vouch token", ctx do
      vt = build_vouch_token(ctx, "device.BK-001.storage.write")
      cs = Validation.validate_vouch_token_insert(vt)
      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects a forged signature", ctx do
      vt =
        ctx
        |> build_vouch_token("device.BK-001.storage.write")
        |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

      cs = Validation.validate_vouch_token_insert(vt)
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :sign_b64)
    end
  end

  describe "validate_vouch_token_update/2" do
    test "accepts an update with newer timestamp", ctx do
      existing = build_vouch_token(ctx, "device.BK-001.storage.read", ts: 1000)
      update = build_vouch_token(ctx, "device.BK-001.storage.read", ts: 2000, deleted_flag: true)

      cs = Validation.validate_vouch_token_update(existing, update)
      assert cs.valid?, inspect(cs.errors)
    end

    test "rejects a stale update", ctx do
      existing = build_vouch_token(ctx, "device.BK-001.storage.read", ts: 2000)
      update = build_vouch_token(ctx, "device.BK-001.storage.read", ts: 1000)

      cs = Validation.validate_vouch_token_update(existing, update)
      refute cs.valid?
    end

    test "rejects an update with forged signature", ctx do
      existing = build_vouch_token(ctx, "device.BK-001.storage.read", ts: 1000)

      update =
        ctx
        |> build_vouch_token("device.BK-001.storage.read", ts: 2000)
        |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

      cs = Validation.validate_vouch_token_update(existing, update)
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :sign_b64)
    end
  end

  defp build_vouch_token(ctx, kind, opts \\ []) do
    vt = %VouchToken{
      kind: kind,
      issuer_hash: ctx.issuer_hash,
      subject_hash: ctx.subject_hash,
      owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond)),
      deleted_flag: Keyword.get(opts, :deleted_flag, false)
    }

    sign_with_key(vt, ctx.issuer.sign_skey)
  end
end
