defmodule Chat.Data.ReviewWriteTokenValidationTest do
  @moduledoc "Validation tests for review write token insert/update (signature, timestamp, auth)."
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewWriteToken, as: ReviewWriteTokenData
  alias Chat.Data.ReviewWriteToken.Validation
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenSignHash
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

  describe "validate_review_write_token_insert/1" do
    test "accepts a validly signed token", ctx do
      token = build_token(ctx)
      changeset = Validation.validate_review_write_token_insert(token)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects a token signed by a stranger", ctx do
      token = build_token(ctx, signer: ctx.stranger)
      changeset = Validation.validate_review_write_token_insert(token)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end

    test "rejects a token with forged signature", ctx do
      token =
        ctx
        |> build_token()
        |> Map.put(:sign_b64, :crypto.strong_rand_bytes(64))

      changeset = Validation.validate_review_write_token_insert(token)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end
  end

  describe "validate_review_write_token_update/2" do
    test "accepts an update with newer timestamp signed by bot", ctx do
      existing = insert_token(ctx)
      updated = build_update(existing, ctx.bot_identity, deleted_flag: true)
      changeset = Validation.validate_review_write_token_update(existing, updated)
      assert changeset.valid?, inspect(changeset.errors)
    end

    test "rejects an update signed by owner", ctx do
      existing = insert_token(ctx)
      updated = build_update(existing, ctx.owner, deleted_flag: true)
      changeset = Validation.validate_review_write_token_update(existing, updated)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end

    test "rejects a stale update (timestamp not newer)", ctx do
      existing = insert_token(ctx, owner_timestamp: 2000)
      updated = build_update(existing, ctx.bot_identity, owner_timestamp: 1000)
      changeset = Validation.validate_review_write_token_update(existing, updated)
      refute changeset.valid?
    end

    test "rejects an update signed by a stranger", ctx do
      existing = insert_token(ctx)
      updated = build_update(existing, ctx.stranger, deleted_flag: true)
      changeset = Validation.validate_review_write_token_update(existing, updated)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end
  end

  describe "review_write_token_allowed/2" do
    test "accepts PoP signed by review bot", ctx do
      operation = insert_operation(ctx.bot_hash)
      pop_context = sign_challenge(ctx.bot_identity)
      assert :ok = Validation.review_write_token_allowed(operation, pop_context)
    end

    test "rejects PoP signed by origin identity", ctx do
      operation = insert_operation(ctx.bot_hash)
      pop_context = sign_challenge(ctx.origin_identity)

      assert {:error, "Invalid operation"} =
               Validation.review_write_token_allowed(operation, pop_context)
    end

    test "rejects PoP signed by a stranger", ctx do
      operation = insert_operation(ctx.bot_hash)
      pop_context = sign_challenge(ctx.stranger)

      assert {:error, "Invalid operation"} =
               Validation.review_write_token_allowed(operation, pop_context)
    end
  end

  describe "upsert LWW" do
    test "newer timestamp wins", ctx do
      nonce = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      insert_token(ctx, owner_timestamp: 1000, nonce: nonce)
      newer = build_token(ctx, owner_timestamp: 2000, deleted_flag: true, nonce: nonce)

      changeset =
        %ReviewWriteToken{}
        |> ReviewWriteToken.create_changeset(Map.from_struct(newer))

      assert {:ok, result} = ReviewWriteTokenData.upsert_review_write_token(changeset)
      assert result.deleted_flag == true
    end

    test "stale timestamp is ignored", ctx do
      nonce = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      insert_token(ctx, owner_timestamp: 2000, nonce: nonce)
      stale = build_token(ctx, owner_timestamp: 1000, deleted_flag: true, nonce: nonce)

      changeset =
        %ReviewWriteToken{}
        |> ReviewWriteToken.create_changeset(Map.from_struct(stale))

      {:ok, _} = ReviewWriteTokenData.upsert_review_write_token(changeset)
      reloaded = ReviewWriteTokenData.get_review_write_token(nonce)
      assert reloaded.deleted_flag == false
    end
  end

  # --- Helpers ---

  defp build_token(ctx, opts \\ []) do
    signer = Keyword.get(opts, :signer, ctx.bot_identity)
    deleted_flag = Keyword.get(opts, :deleted_flag, false)
    owner_timestamp = Keyword.get(opts, :owner_timestamp, System.os_time(:millisecond))

    nonce =
      Keyword.get_lazy(opts, :nonce, fn ->
        Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      end)

    token = %ReviewWriteToken{
      nonce: nonce,
      origin_hash: ctx.origin_hash,
      review_bot_hash: ctx.bot_hash,
      origin_order_hash: nil,
      parent_nonce: nil,
      user_hash: nil,
      review_hash: nil,
      deleted_flag: deleted_flag,
      owner_timestamp: owner_timestamp
    }

    sign_with_hash(token, signer.sign_skey, &ReviewWriteTokenSignHash.from_binary/1)
  end

  defp insert_token(ctx, opts \\ []) do
    token = build_token(ctx, opts)

    changeset =
      %ReviewWriteToken{}
      |> ReviewWriteToken.create_changeset(Map.from_struct(token))

    {:ok, inserted} = ReviewWriteTokenData.upsert_review_write_token(changeset)
    inserted
  end

  defp build_update(existing, signer, opts \\ []) do
    deleted_flag = Keyword.get(opts, :deleted_flag, existing.deleted_flag)
    owner_timestamp = Keyword.get(opts, :owner_timestamp, existing.owner_timestamp + 1)

    updated = %{existing | deleted_flag: deleted_flag, owner_timestamp: owner_timestamp}
    sign_with_hash(updated, signer.sign_skey, &ReviewWriteTokenSignHash.from_binary/1)
  end

  defp insert_operation(review_bot_hash) do
    %Operation{
      index: 0,
      operation: :insert,
      relation: "review_write_tokens",
      data: nil,
      changes: %{"review_bot_hash" => review_bot_hash}
    }
  end

  defp sign_challenge(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    signature = :crypto.sign(:mldsa87, :none, challenge, identity.sign_skey)
    %{challenge: challenge, signature: signature}
  end
end
