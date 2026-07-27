defmodule ChatWeb.ElectricLive.ModerationSandboxLive.EntriesTest do
  @moduledoc """
  Moderation queue classification: what the origin identity can read, and which
  action would actually change public visibility.
  """
  use ExUnit.Case, async: true

  alias Chat.Data.ReviewPasswordCandidate.Promotion.Candidates
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Entries
  alias EnigmaPq

  @origin_hash "u_" <> String.duplicate("a", 128)
  @author_hash "u_" <> String.duplicate("b", 128)

  setup do
    {crypt_pkey, crypt_skey} = EnigmaPq.generate_crypt_keypair()
    password = :crypto.strong_rand_bytes(32)

    %{
      crypt_pkey: crypt_pkey,
      crypt_skey: crypt_skey,
      password: password,
      review: build_review(password, [5, "", "great coffee"])
    }
  end

  describe "build/5" do
    test "pre-moderation: post right unlocks the review before it is public", ctx do
      post_right = wrap_right(ReviewPostRight, ctx, ctx.password, 200)

      [entry] = Entries.build([ctx.review], [], [post_right], [], ctx.crypt_skey)

      assert entry.state == :pending
      assert entry.password_source == :post_right
      assert entry.rating == 5
      assert entry.text == "great coffee"
      assert entry.publish_effective?
    end

    test "published review is public and revocable", ctx do
      password_row = password_row(ctx, to_b64(ctx.password), 200)
      revoke_right = wrap_right(ReviewRevokeRight, ctx, nil, 201)

      [entry] = Entries.build([ctx.review], [password_row], [], [revoke_right], ctx.crypt_skey)

      assert entry.state == :public
      assert entry.password_source == :published
      assert entry.text == "great coffee"
      assert entry.revoke_effective?
    end

    test "revoked review stays hidden — an older post right cannot supersede it", ctx do
      rows = [password_row(ctx, to_b64(ctx.password), 200), password_row(ctx, nil, 201)]
      post_right = wrap_right(ReviewPostRight, ctx, ctx.password, 200)

      [entry] = Entries.build([ctx.review], rows, [post_right], [], ctx.crypt_skey)

      assert entry.state == :hidden
      assert entry.latest_timestamp == 201
      refute entry.publish_effective?
    end

    test "revoked review stays readable to the origin via the superseded password row", ctx do
      rows = [password_row(ctx, to_b64(ctx.password), 200), password_row(ctx, nil, 201)]

      [entry] = Entries.build([ctx.review], rows, [], [], ctx.crypt_skey)

      assert entry.state == :hidden
      assert entry.text == "great coffee"
      assert entry.password_source == :published
    end

    test "right wrapped for another origin does not unwrap", ctx do
      {other_pkey, _other_skey} = EnigmaPq.generate_crypt_keypair()

      foreign_right =
        wrap_right(ReviewPostRight, %{ctx | crypt_pkey: other_pkey}, ctx.password, 200)

      [entry] = Entries.build([ctx.review], [], [foreign_right], [], ctx.crypt_skey)

      assert entry.post_right.status == :error
      assert entry.post_right.reason =~ "decryption failed"
      assert entry.content_error == :no_password
      refute entry.publish_effective?
    end

    test "review without rights or passwords is pending and locked", ctx do
      [entry] = Entries.build([ctx.review], [], [], [], ctx.crypt_skey)

      assert entry.state == :pending
      assert entry.content_error == :no_password
      assert entry.post_right == nil
      assert entry.revoke_right == nil
    end

    test "deleted reviews are dropped and the rest sorted newest first", ctx do
      older = %{ctx.review | review_hash: review_hash(), owner_timestamp: 50}
      deleted = %{ctx.review | review_hash: review_hash(), deleted_flag: true}

      entries = Entries.build([older, ctx.review, deleted], [], [], [], ctx.crypt_skey)

      assert Enum.map(entries, & &1.owner_timestamp) == [100, 50]
    end
  end

  # Helpers

  defp build_review(password, content) do
    %Review{
      review_hash: review_hash(),
      origin_hash: @origin_hash,
      author_hash: @author_hash,
      content_b64: content |> Jason.encode!() |> EnigmaPq.aes_gcm_encrypt(password) |> to_b64(),
      deleted_flag: false,
      owner_timestamp: 100
    }
  end

  defp wrap_right(schema, ctx, password, timestamp) do
    {_shared_secret, kem_ciphertext, wrapped} =
      ctx.review
      |> candidate_row(password, timestamp)
      |> Candidates.wrap_candidate_for_origin(ctx.crypt_pkey)

    struct(schema, %{
      review_hash: ctx.review.review_hash,
      origin_hash: @origin_hash,
      author_hash: @author_hash,
      kem_ciphertext_b64: to_b64(kem_ciphertext),
      wrapped_row_b64: to_b64(wrapped),
      deleted_flag: false,
      owner_timestamp: timestamp
    })
  end

  defp candidate_row(review, password, timestamp) do
    %{
      review_hash: review.review_hash,
      sign_hash: sign_hash(),
      origin_hash: @origin_hash,
      password_b64: password,
      author_hash: @author_hash,
      owner_timestamp: timestamp,
      sign_b64: :crypto.strong_rand_bytes(16)
    }
  end

  defp password_row(ctx, password_b64, timestamp) do
    %ReviewPublicPassword{
      review_hash: ctx.review.review_hash,
      sign_hash: sign_hash(),
      origin_hash: @origin_hash,
      password_b64: password_b64,
      author_hash: @author_hash,
      deleted_flag: false,
      owner_timestamp: timestamp
    }
  end

  defp review_hash, do: "rv_" <> Base.encode16(:crypto.strong_rand_bytes(64), case: :lower)
  defp sign_hash, do: "rps_" <> Base.encode16(:crypto.strong_rand_bytes(64), case: :lower)

  defp to_b64(binary), do: Base.encode64(binary, padding: false)
end
