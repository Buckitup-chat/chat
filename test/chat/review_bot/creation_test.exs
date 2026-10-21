defmodule Chat.ReviewBot.CreationTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.Integrity
  alias Chat.Data.OriginBot, as: OriginBotData
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.User
  alias Chat.Data.VouchToken
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias Chat.ReviewBot.Creation
  alias Chat.ReviewBot.Identity

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    insert_user_card(owner)
    insert_user_card(origin_identity)
    insert_origin(origin_identity, owner)

    origin_card = User.extract_pq_card(origin_identity)

    {:ok, owner: owner, origin_identity: origin_identity, origin_card: origin_card}
  end

  describe "generate_identity/1" do
    test "generates a named identity" do
      bot = Creation.generate_identity("CoffeeShop")
      assert bot.name == "ReviewBot_CoffeeShop"
      assert is_binary(bot.sign_skey)
      assert is_binary(bot.crypt_skey)
    end
  end

  describe "origin_bot/5" do
    test "builds a signed origin_bot with KEM-wrapped identity", ctx do
      bot = Creation.generate_identity("CoffeeShop")
      bot_card = User.extract_pq_card(bot)
      insert_user_card(bot)

      ob =
        Creation.origin_bot(
          bot_card.user_hash,
          bot,
          ctx.origin_card.user_hash,
          ctx.origin_identity.crypt_pkey,
          ctx.origin_identity.sign_skey
        )

      assert ob.bot_hash == bot_card.user_hash
      assert ob.origin_hash == ctx.origin_card.user_hash
      assert ob.deleted_flag == false
      assert is_binary(ob.secret_b64)
      assert is_binary(ob.encrypted_identity_b64)
      assert :ok = Integrity.verify_signature(ob)
    end

    test "wrapped identity can be unwrapped with origin crypt_skey", ctx do
      bot = Creation.generate_identity("CoffeeShop")
      bot_card = User.extract_pq_card(bot)
      insert_user_card(bot)

      ob =
        Creation.origin_bot(
          bot_card.user_hash,
          bot,
          ctx.origin_card.user_hash,
          ctx.origin_identity.crypt_pkey,
          ctx.origin_identity.sign_skey
        )

      assert {:ok, unwrapped} =
               Identity.unwrap(
                 ob.secret_b64,
                 ob.encrypted_identity_b64,
                 ctx.origin_identity.crypt_skey
               )

      assert unwrapped.sign_skey == bot.sign_skey
      assert unwrapped.crypt_skey == bot.crypt_skey
    end
  end

  describe "origin_vouch/3" do
    test "builds a vouch with correct scope", ctx do
      bot = Creation.generate_identity("CoffeeShop")
      bot_card = User.extract_pq_card(bot)

      vouch =
        Creation.origin_vouch(
          ctx.origin_card.user_hash,
          ctx.origin_identity.sign_skey,
          bot_card.user_hash
        )

      assert vouch.kind == "origins.#{ctx.origin_card.user_hash}.reviews.write"
      assert vouch.issuer_hash == ctx.origin_card.user_hash
      assert vouch.subject_hash == bot_card.user_hash
      assert vouch.deleted_flag == false
      assert :ok = Integrity.verify_signature(vouch)
    end
  end

  describe "device_vouches/4" do
    test "builds vouches for all required shapes", ctx do
      bot = Creation.generate_identity("CoffeeShop")
      bot_card = User.extract_pq_card(bot)
      insert_user_card(bot)

      owner_card = User.extract_pq_card(ctx.owner)

      vouches =
        Creation.device_vouches(
          owner_card.user_hash,
          ctx.owner.sign_skey,
          bot_card.user_hash,
          "test-device"
        )

      assert length(vouches) == 7

      kinds = Enum.map(vouches, & &1.kind)
      assert "device.test-device.storage.write.review_write_token" in kinds
      assert "device.test-device.storage.write.review" in kinds
      assert "device.test-device.storage.write.review_list" in kinds

      Enum.each(vouches, fn vt ->
        assert vt.issuer_hash == owner_card.user_hash
        assert vt.subject_hash == bot_card.user_hash
        assert :ok = Integrity.verify_signature(vt)
      end)
    end
  end

  describe "full creation flow" do
    test "creates bot, persists rows, verifies vouch chain", ctx do
      bot = Creation.generate_identity("CoffeeShop")
      bot_card = User.extract_pq_card(bot)

      {:ok, _} = ShapeWriter.write(:user_card, :insert, bot_card)

      ob =
        Creation.origin_bot(
          bot_card.user_hash,
          bot,
          ctx.origin_card.user_hash,
          ctx.origin_identity.crypt_pkey,
          ctx.origin_identity.sign_skey
        )

      changeset = %OriginBot{} |> OriginBot.create_changeset(Map.from_struct(ob))
      {:ok, persisted} = OriginBotData.upsert_origin_bot(changeset)
      assert persisted.bot_hash == bot_card.user_hash

      vouch =
        Creation.origin_vouch(
          ctx.origin_card.user_hash,
          ctx.origin_identity.sign_skey,
          bot_card.user_hash
        )

      {:ok, _} = ShapeWriter.write(:vouch_token, :insert, vouch)

      assert {:ok, _distance} =
               VouchToken.chain_distance(
                 ctx.origin_card.user_hash,
                 bot_card.user_hash,
                 "origins.#{ctx.origin_card.user_hash}.reviews.write"
               )
    end
  end
end
