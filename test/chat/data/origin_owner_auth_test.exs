defmodule Chat.Data.OriginOwnerAuthTest do
  @moduledoc """
  Tests for owner-authenticated origin operations via `origin_allowed/2` and
  owner-signed payload validation via `origin_validate/3`.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.Integrity
  alias Chat.Data.Origin.Validation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.User
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")
    author = User.generate_pq_identity("Reviewer")
    stranger = User.generate_pq_identity("Stranger")

    _owner_card = insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)
    _author_card = insert_user_card(author)
    _stranger_card = insert_user_card(stranger)

    insert_origin(origin_identity, owner)

    origin_hash = origin_card.user_hash

    {:ok,
     owner: owner,
     origin_identity: origin_identity,
     author: author,
     stranger: stranger,
     origin_hash: origin_hash}
  end

  describe "origin_allowed/2 — owner auth" do
    test "accepts update signed by owner when no reviews exist", ctx do
      operation = update_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.owner)

      assert :ok = Validation.origin_allowed(operation, pop_context)
    end

    test "accepts update signed by owner when all reviews are moderated", ctx do
      review = insert_review(ctx.author, ctx.origin_hash)
      insert_public_password(ctx.author, review, ctx.origin_hash)

      operation = update_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.owner)

      assert :ok = Validation.origin_allowed(operation, pop_context)
    end

    test "rejects update signed by owner when a review is pending", ctx do
      insert_review(ctx.author, ctx.origin_hash)

      operation = update_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.owner)

      assert {:error, "Cannot modify origin while reviews are pending moderation"} =
               Validation.origin_allowed(operation, pop_context)
    end

    test "rejects insert signed by owner", ctx do
      operation = insert_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.owner)

      assert {:error, "Invalid operation"} = Validation.origin_allowed(operation, pop_context)
    end

    test "rejects update signed by origin identity", ctx do
      operation = update_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.origin_identity)

      assert {:error, _} = Validation.origin_allowed(operation, pop_context)
    end

    test "rejects update signed by a stranger", ctx do
      operation = update_operation(ctx.origin_hash)
      pop_context = sign_challenge(ctx.stranger)

      assert {:error, "Invalid operation"} = Validation.origin_allowed(operation, pop_context)
    end
  end

  describe "origin_validate/3 — owner-signed payload" do
    test "accepts update with payload signed by owner", ctx do
      existing = Chat.Data.Origin.get_origin(ctx.origin_hash)
      {sign_b64, sign_hash} = sign_payload(existing, ctx.owner.sign_skey, "Updated Name")

      changes = %{
        "name" => "Updated Name",
        "moderation_mode" => "none",
        "deleted_flag" => false,
        "owner_timestamp" => existing.owner_timestamp + 1,
        "sign_b64" => sign_b64,
        "sign_hash" => sign_hash
      }

      changeset = Validation.origin_validate(existing, changes, :update)
      assert changeset.valid?
    end

    test "accepts update with payload signed by origin identity", ctx do
      existing = Chat.Data.Origin.get_origin(ctx.origin_hash)
      {sign_b64, sign_hash} = sign_payload(existing, ctx.origin_identity.sign_skey, "Updated")

      changes = %{
        "name" => "Updated",
        "moderation_mode" => "none",
        "deleted_flag" => false,
        "owner_timestamp" => existing.owner_timestamp + 1,
        "sign_b64" => sign_b64,
        "sign_hash" => sign_hash
      }

      changeset = Validation.origin_validate(existing, changes, :update)
      assert changeset.valid?
    end

    test "rejects update with payload signed by stranger", ctx do
      existing = Chat.Data.Origin.get_origin(ctx.origin_hash)
      {sign_b64, sign_hash} = sign_payload(existing, ctx.stranger.sign_skey, "Hacked")

      changes = %{
        "name" => "Hacked",
        "moderation_mode" => "none",
        "deleted_flag" => false,
        "owner_timestamp" => existing.owner_timestamp + 1,
        "sign_b64" => sign_b64,
        "sign_hash" => sign_hash
      }

      changeset = Validation.origin_validate(existing, changes, :update)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :sign_b64)
    end
  end

  describe "has_pending_reviews?/1" do
    test "returns false when no reviews exist", ctx do
      refute Validation.has_pending_reviews?(ctx.origin_hash)
    end

    test "returns true when a review has no public password row", ctx do
      insert_review(ctx.author, ctx.origin_hash)

      assert Validation.has_pending_reviews?(ctx.origin_hash)
    end

    test "returns false when all reviews have a public password row", ctx do
      review = insert_review(ctx.author, ctx.origin_hash)
      insert_public_password(ctx.author, review, ctx.origin_hash)

      refute Validation.has_pending_reviews?(ctx.origin_hash)
    end

    test "ignores deleted reviews", ctx do
      review = insert_review(ctx.author, ctx.origin_hash)

      {:ok, _} =
        Chat.Data.Review.upsert_review(
          Chat.Data.Schemas.Review.update_changeset(review, %{
            deleted_flag: true,
            owner_timestamp: review.owner_timestamp + 1,
            content_b64: review.content_b64,
            sign_b64: review.sign_b64,
            sign_hash: review.sign_hash
          })
        )

      refute Validation.has_pending_reviews?(ctx.origin_hash)
    end
  end

  # --- Helpers ---

  defp update_operation(origin_hash) do
    %Operation{
      index: 0,
      operation: :update,
      relation: "origins",
      data: %{"origin_hash" => origin_hash},
      changes: %{"name" => "Updated Name"}
    }
  end

  defp insert_operation(origin_hash) do
    %Operation{
      index: 0,
      operation: :insert,
      relation: "origins",
      data: nil,
      changes: %{"origin_hash" => origin_hash}
    }
  end

  defp sign_challenge(identity) do
    challenge = :crypto.strong_rand_bytes(32)
    signature = :crypto.sign(:mldsa87, :none, challenge, identity.sign_skey)
    %{challenge: challenge, signature: signature}
  end

  defp sign_payload(existing, sign_skey, new_name) do
    origin_struct = %Origin{
      origin_hash: existing.origin_hash,
      owner_hash: existing.owner_hash,
      owner_cert: existing.owner_cert,
      name: new_name,
      moderation_mode: existing.moderation_mode,
      deleted_flag: false,
      owner_timestamp: existing.owner_timestamp + 1
    }

    sign_b64 =
      origin_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> OriginSignHash.from_binary()

    {sign_b64, sign_hash}
  end
end
