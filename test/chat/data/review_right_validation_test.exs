defmodule Chat.Data.ReviewRightValidationTest do
  @moduledoc """
  Cross-table binding for review_post_right / review_revoke_right inserts.

  Rights are inserted unsigned (the author's signature is added by a later
  update), so the insert path cannot verify a signature. It must instead bind
  the right to an existing review: same author, same origin.
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewPostRight.Validation, as: PostRightValidation
  alias Chat.Data.ReviewRevokeRight.Validation, as: RevokeRightValidation
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.User

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    author = User.generate_pq_identity("Author")
    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)

    insert_origin(origin_identity, owner, :pre)
    review = insert_review(author, origin_card.user_hash)

    {:ok, author_hash: author_card.user_hash, origin_hash: origin_card.user_hash, review: review}
  end

  for {label, schema, validate} <- [
        {"post_right", ReviewPostRight, &PostRightValidation.validate_post_right_insert/1},
        {"revoke_right", ReviewRevokeRight, &RevokeRightValidation.validate_revoke_right_insert/1}
      ] do
    describe label do
      test "accepts a right bound to its review", ctx do
        cs =
          unquote(schema)
          |> build_right(ctx.review, ctx.author_hash, ctx.origin_hash)
          |> unquote(validate).()

        assert cs.valid?, inspect(cs.errors)
      end

      test "rejects a right whose author does not match the review", ctx do
        other = User.extract_pq_card(User.generate_pq_identity("Mallory")).user_hash

        cs =
          unquote(schema)
          |> build_right(ctx.review, other, ctx.origin_hash)
          |> unquote(validate).()

        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :author_hash)
      end

      test "rejects a right whose origin does not match the review", ctx do
        other = User.extract_pq_card(User.generate_pq_identity("OtherShop")).user_hash

        cs =
          unquote(schema)
          |> build_right(ctx.review, ctx.author_hash, other)
          |> unquote(validate).()

        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :origin_hash)
      end

      test "rejects a right for a review that does not exist", ctx do
        phantom = %{
          ctx.review
          | review_hash: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
        }

        cs =
          unquote(schema)
          |> build_right(phantom, ctx.author_hash, ctx.origin_hash)
          |> unquote(validate).()

        refute cs.valid?
        assert Keyword.has_key?(cs.errors, :review_hash)
      end
    end
  end

  # --- Helpers ---

  defp build_right(schema, review, author_hash, origin_hash) do
    struct(schema, %{
      review_hash: review.review_hash,
      origin_hash: origin_hash,
      author_hash: author_hash,
      kem_ciphertext_b64: :crypto.strong_rand_bytes(32),
      wrapped_row_b64: :crypto.strong_rand_bytes(64),
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    })
  end
end
