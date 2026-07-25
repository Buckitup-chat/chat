defmodule Chat.Data.ReviewShapesTest do
  @moduledoc """
  Shape-contract assertions for review shapes: `shape_name`,
  `schema_module`, `sync_required_parents`, and `sync_derive_fields`.
  Pure functions — no database.
  """
  use ExUnit.Case, async: true

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias Chat.Data.Shapes
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.ReviewSignHash

  describe "Review shape" do
    test "shape_name" do
      assert_shape_name(Shapes.Review, :review)
    end

    test "schema_module" do
      assert_schema_module(Shapes.Review, Review)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.Review)
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      assert_derives_sign_hash(Shapes.Review, Review, ReviewSignHash)
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert_nil_sign_hash(Shapes.Review, Review)
    end
  end

  describe "ReviewPublicPasswords shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewPublicPasswords, :review_public_passwords)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewPublicPasswords, ReviewPublicPassword)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.ReviewPublicPasswords)
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      assert_derives_sign_hash(
        Shapes.ReviewPublicPasswords,
        ReviewPublicPassword,
        ReviewPasswordSignHash
      )
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert_nil_sign_hash(Shapes.ReviewPublicPasswords, ReviewPublicPassword)
    end
  end

  describe "ReviewPostRight shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewPostRight, :review_post_right)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewPostRight, ReviewPostRight)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.ReviewPostRight)
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      assert_derives_sign_hash(Shapes.ReviewPostRight, ReviewPostRight, ReviewPostRightSignHash)
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert_nil_sign_hash(Shapes.ReviewPostRight, ReviewPostRight)
    end
  end

  describe "ReviewRevokeRight shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewRevokeRight, :review_revoke_right)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewRevokeRight, ReviewRevokeRight)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.ReviewRevokeRight)
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      assert_derives_sign_hash(
        Shapes.ReviewRevokeRight,
        ReviewRevokeRight,
        ReviewRevokeRightSignHash
      )
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert_nil_sign_hash(Shapes.ReviewRevokeRight, ReviewRevokeRight)
    end
  end

  describe "ReviewList shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewList, :review_list)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewList, ReviewList)
    end

    test "sync_required_parents returns user_card dependency for list owner" do
      assert_requires_parent_user_card(Shapes.ReviewList, :user_hash)
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      assert_derives_sign_hash(Shapes.ReviewList, ReviewList, ReviewListSignHash)
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert_nil_sign_hash(Shapes.ReviewList, ReviewList)
    end
  end

  describe "shape registry" do
    test "all eight review shapes are registered" do
      names = Shapes.shape_names()

      for name <- [
            :review,
            :review_public_passwords,
            :review_post_right,
            :review_revoke_right,
            :review_password_candidate,
            :review_post_right_candidate,
            :review_revoke_right_candidate,
            :review_list
          ] do
        assert name in names
      end
    end
  end

  describe "ReviewPasswordCandidate shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewPasswordCandidate, :review_password_candidate)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewPasswordCandidate, ReviewPasswordCandidate)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.ReviewPasswordCandidate)
    end
  end

  describe "ReviewPostRightCandidate shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewPostRightCandidate, :review_post_right_candidate)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewPostRightCandidate, ReviewPostRightCandidate)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.ReviewPostRightCandidate)
    end
  end

  describe "ReviewRevokeRightCandidate shape" do
    test "shape_name" do
      assert_shape_name(Shapes.ReviewRevokeRightCandidate, :review_revoke_right_candidate)
    end

    test "schema_module" do
      assert_schema_module(Shapes.ReviewRevokeRightCandidate, ReviewRevokeRightCandidate)
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert_requires_parent_user_card(Shapes.ReviewRevokeRightCandidate)
    end
  end

  # Helpers

  defp assert_shape_name(shape, expected) do
    assert shape.shape_name() == expected
  end

  defp assert_schema_module(shape, expected) do
    assert shape.schema_module() == expected
  end

  defp assert_requires_parent_user_card(shape, hash_key \\ :author_hash) do
    assert [{:user_card, "u_abc"}] = shape.sync_required_parents(:insert, %{hash_key => "u_abc"})
  end

  defp assert_derives_sign_hash(shape, schema_mod, hash_type) do
    sign_b64 = :crypto.strong_rand_bytes(32)
    expected = sign_b64 |> EnigmaPq.hash() |> hash_type.from_binary()

    assert %{sign_hash: ^expected} =
             shape.sync_derive_fields(struct!(schema_mod, sign_b64: sign_b64))
  end

  defp assert_nil_sign_hash(shape, schema_mod) do
    assert %{sign_hash: nil} =
             shape.sync_derive_fields(struct!(schema_mod, sign_b64: nil))
  end
end
