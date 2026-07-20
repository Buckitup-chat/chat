defmodule Chat.Data.OriginValidationTest do
  @moduledoc """
  Owner-certificate validation for origins.

  `owner_cert = ML-DSA-87.sign(origin_sign_pkey, owner_sign_skey)` binds an
  origin identity to its owner. `Chat.Data.Origin.Validation` must reject a
  forged cert — a cert not produced by the claimed owner's signing key.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.Origin.Validation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias EnigmaPq

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    attacker = User.generate_pq_identity("Attacker")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    owner_card = insert_user_card(owner)
    _attacker_card = insert_user_card(attacker)
    origin_card = insert_user_card(origin_identity)

    {:ok,
     owner: owner,
     attacker: attacker,
     origin_identity: origin_identity,
     owner_hash: owner_card.user_hash,
     origin_pkey: origin_card.sign_pkey}
  end

  test "accepts an origin with a valid owner_cert", ctx do
    owner_cert = EnigmaPq.sign(ctx.origin_pkey, ctx.owner.sign_skey)

    cs = validate(ctx, owner_cert)

    assert cs.valid?, inspect(cs.errors)
  end

  test "rejects a forged (random) owner_cert", ctx do
    cs = validate(ctx, :crypto.strong_rand_bytes(64))

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :owner_cert)
  end

  test "rejects an owner_cert signed by someone other than the owner", ctx do
    forged = EnigmaPq.sign(ctx.origin_pkey, ctx.attacker.sign_skey)

    cs = validate(ctx, forged)

    refute cs.valid?
    assert Keyword.has_key?(cs.errors, :owner_cert)
  end

  # --- Helpers ---

  defp validate(ctx, owner_cert) do
    origin = %Origin{
      origin_hash: User.extract_pq_card(ctx.origin_identity).user_hash,
      owner_hash: ctx.owner_hash,
      owner_cert: owner_cert,
      name: "Test Origin",
      moderation_mode: :none,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    # The origin self-signature covers owner_cert, so sign after setting it —
    # this keeps the self-signature valid and isolates the owner_cert check.
    sign_b64 =
      origin |> Integrity.signature_payload() |> EnigmaPq.sign(ctx.origin_identity.sign_skey)

    sign_hash = sign_b64 |> EnigmaPq.hash() |> OriginSignHash.from_binary()

    %{origin | sign_b64: sign_b64, sign_hash: sign_hash}
    |> Validation.validate_origin_insert()
  end

  defp insert_user_card(identity) do
    card =
      identity
      |> User.extract_pq_card()
      |> then(fn card ->
        sign_b64 = card |> Integrity.signature_payload() |> EnigmaPq.sign(identity.sign_skey)
        %{card | sign_b64: sign_b64}
      end)

    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end
end
