defmodule Chat.Data.ReviewListAccessTest do
  @moduledoc """
  A review awaiting pre-moderation has no `review_public_passwords` row, so its
  `review_password` is reachable only through `review_list` — the path the author's
  other devices and their contacts read (docs/proposal/reviews.md "Contacts").
  """
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  import Chat.Test.ReviewFixtures

  alias Chat.Data.ReviewList
  alias Chat.Data.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewList, as: ReviewListSchema
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias EnigmaPq

  @content "Great coffee!"

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)

    author = User.generate_pq_identity("Author")
    owner = User.generate_pq_identity("Owner")
    origin_identity = User.generate_pq_identity("CoffeeShop")

    author_card = insert_user_card(author)
    _owner_card = insert_user_card(owner)
    origin_card = insert_user_card(origin_identity)

    insert_origin(origin_identity, owner, :pre)

    {:ok, author: author, author_hash: author_card.user_hash, origin_hash: origin_card.user_hash}
  end

  describe "review awaiting pre-moderation" do
    test "author reads its password from review_list while it is unpublished", ctx do
      review = review_awaiting_moderation(ctx)
      list_password = :crypto.strong_rand_bytes(32)

      share_with_contacts(ctx, review, list_password)

      assert ReviewPublicPassword.get_latest_for_review(review.review_hash) == nil

      assert %{password_b64: shared_password} =
               ReviewList.get_review_list_entry(ctx.author_hash, review.review_hash)

      review_password = EnigmaPq.aes_gcm_decrypt(shared_password, list_password)

      assert review_password == review.review_password
      assert EnigmaPq.aes_gcm_decrypt(review.content_b64, review_password) == @content
    end
  end

  # Helpers

  defp review_awaiting_moderation(%{author: author, origin_hash: origin_hash}) do
    review_password = :crypto.strong_rand_bytes(32)

    review =
      insert_review(author, origin_hash,
        review_password: review_password,
        content_b64: EnigmaPq.aes_gcm_encrypt(@content, review_password)
      )

    post_right = insert_post_right(author, review, origin_hash)
    revoke_right = insert_revoke_right(author, review, origin_hash)

    Map.merge(review, %{
      post_right_sign_hash: post_right.sign_hash,
      revoke_right_sign_hash: revoke_right.sign_hash
    })
  end

  # A row that fails the pre-mode proof gate is dropped silently by the shape, so
  # reading it back afterwards is what proves it passed.
  defp share_with_contacts(ctx, review, list_password) do
    entry = %ReviewListSchema{
      user_hash: ctx.author_hash,
      review_hash: review.review_hash,
      origin_hash: ctx.origin_hash,
      password_b64: EnigmaPq.aes_gcm_encrypt(review.review_password, list_password),
      review_password_sign_hash: nil,
      post_right_sign_hash: review.post_right_sign_hash,
      revoke_right_sign_hash: review.revoke_right_sign_hash,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(entry, ctx.author.sign_skey, &ReviewListSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:review_list, :insert, signed)
  end
end
