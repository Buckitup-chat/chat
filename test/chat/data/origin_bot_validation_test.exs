defmodule Chat.Data.OriginBotValidationTest do
  @moduledoc "Validation tests for origin bot insert/update (signature, timestamp, auth)."
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.OriginBot, as: OriginBotData
  alias Chat.Data.OriginBot.Validation
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.User
  alias Phoenix.Sync.Writer.Operation

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")
    bot_identity = User.generate_pq_identity("ReviewBot_CoffeeShop")
    stranger = User.generate_pq_identity("Stranger")

    insert_user_card(owner)
    insert_user_card(origin_identity)
    insert_user_card(bot_identity)
    insert_user_card(stranger)

    insert_origin(origin_identity, owner)

    origin_hash = User.extract_pq_card(origin_identity).user_hash
    bot_hash = User.extract_pq_card(bot_identity).user_hash

    {:ok,
     owner: owner,
     origin_identity: origin_identity,
     bot_identity: bot_identity,
     stranger: stranger,
     origin_hash: origin_hash,
     bot_hash: bot_hash}
  end

  describe "validate_origin_bot_insert/1" do
    test "accepts a validly signed bot", ctx do
      bot = build_origin_bot(ctx)
      changeset = Validation.validate_origin_bot_insert(bot)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects a bot signed by a stranger", ctx do
      bot = build_origin_bot(ctx, signer: ctx.stranger)
      changeset = Validation.validate_origin_bot_insert(bot)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end

    test "rejects a bot with forged signature", ctx do
      bot =
        ctx
        |> build_origin_bot()
        |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

      changeset = Validation.validate_origin_bot_insert(bot)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end
  end

  describe "validate_origin_bot_update/2" do
    test "accepts an update with newer timestamp signed by origin", ctx do
      existing = insert_origin_bot(ctx)
      updated = build_update(existing, ctx.origin_identity, deleted_flag: true)
      changeset = Validation.validate_origin_bot_update(existing, updated)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects an update signed by owner", ctx do
      existing = insert_origin_bot(ctx)
      updated = build_update(existing, ctx.owner, deleted_flag: true)
      changeset = Validation.validate_origin_bot_update(existing, updated)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end

    test "rejects a stale update (timestamp not newer)", ctx do
      existing = insert_origin_bot(ctx, owner_timestamp: 2000)
      updated = build_update(existing, ctx.origin_identity, owner_timestamp: 1000)
      changeset = Validation.validate_origin_bot_update(existing, updated)
      refute changeset.valid?
    end

    test "rejects an update signed by a stranger", ctx do
      existing = insert_origin_bot(ctx)
      updated = build_update(existing, ctx.stranger, deleted_flag: true)
      changeset = Validation.validate_origin_bot_update(existing, updated)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end
  end

  describe "origin_bot_allowed/2" do
    test "accepts PoP signed by origin identity", ctx do
      operation = insert_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.origin_identity)
      assert :ok = Validation.origin_bot_allowed(operation, pop_context)
    end

    test "rejects PoP signed by owner", ctx do
      operation = insert_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.owner)
      assert {:error, "Invalid operation"} = Validation.origin_bot_allowed(operation, pop_context)
    end

    test "rejects PoP signed by a stranger", ctx do
      operation = insert_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.stranger)
      assert {:error, "Invalid operation"} = Validation.origin_bot_allowed(operation, pop_context)
    end
  end

  describe "upsert LWW" do
    test "newer timestamp wins", ctx do
      insert_origin_bot(ctx, owner_timestamp: 1000)
      newer = build_origin_bot(ctx, owner_timestamp: 2000, deleted_flag: true)

      changeset =
        %OriginBot{}
        |> OriginBot.create_changeset(Map.from_struct(newer))

      assert {:ok, result} = OriginBotData.upsert_origin_bot(changeset)
      assert result.deleted_flag == true
    end

    test "stale timestamp is ignored", ctx do
      insert_origin_bot(ctx, owner_timestamp: 2000)
      stale = build_origin_bot(ctx, owner_timestamp: 1000, deleted_flag: true)

      changeset =
        %OriginBot{}
        |> OriginBot.create_changeset(Map.from_struct(stale))

      {:ok, _} = OriginBotData.upsert_origin_bot(changeset)
      reloaded = OriginBotData.get_origin_bot(ctx.bot_hash)
      assert reloaded.deleted_flag == false
    end
  end

  # --- Helpers ---

  defp build_origin_bot(ctx, opts \\ []) do
    signer = Keyword.get(opts, :signer, ctx.origin_identity)
    deleted_flag = Keyword.get(opts, :deleted_flag, false)
    owner_timestamp = Keyword.get(opts, :owner_timestamp, System.os_time(:millisecond))

    bot = %OriginBot{
      bot_hash: ctx.bot_hash,
      origin_hash: ctx.origin_hash,
      secret: :crypto.strong_rand_bytes(1568),
      encrypted_identity: :crypto.strong_rand_bytes(128),
      deleted_flag: deleted_flag,
      owner_timestamp: owner_timestamp
    }

    sign_with_hash(bot, signer.sign_skey, &OriginBotSignHash.from_binary/1)
  end

  defp insert_origin_bot(ctx, opts \\ []) do
    bot = build_origin_bot(ctx, opts)

    changeset =
      %OriginBot{}
      |> OriginBot.create_changeset(Map.from_struct(bot))

    {:ok, inserted} = OriginBotData.upsert_origin_bot(changeset)
    inserted
  end

  defp build_update(existing, signer, opts \\ []) do
    deleted_flag = Keyword.get(opts, :deleted_flag, existing.deleted_flag)
    owner_timestamp = Keyword.get(opts, :owner_timestamp, existing.owner_timestamp + 1)

    updated = %{existing | deleted_flag: deleted_flag, owner_timestamp: owner_timestamp}
    sign_with_hash(updated, signer.sign_skey, &OriginBotSignHash.from_binary/1)
  end

  defp insert_operation(origin_hash) do
    %Operation{
      index: 0,
      operation: :insert,
      relation: "origin_bots",
      data: nil,
      changes: %{"origin_hash" => origin_hash}
    }
  end

  defp sign_challenge(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    signature = :crypto.sign(:mldsa87, :none, challenge, identity.sign_skey)
    %{challenge: challenge, signature: signature}
  end
end
