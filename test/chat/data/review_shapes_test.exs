defmodule Chat.Data.ReviewShapesTest do
  @moduledoc """
  Shape-contract assertions for the five review shapes: `shape_name`,
  `schema_module`, `sync_required_parents`, and `sync_derive_fields`.
  Pure functions — no database.
  """
  use ExUnit.Case, async: true

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Shapes
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.ReviewSignHash

  describe "Review shape" do
    test "shape_name" do
      assert Shapes.Review.shape_name() == :review
    end

    test "schema_module" do
      assert Shapes.Review.schema_module() == Review
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert [{:user_card, "u_abc"}] =
               Shapes.Review.sync_required_parents(:insert, %{author_hash: "u_abc"})
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      sign_b64 = :crypto.strong_rand_bytes(32)
      expected = sign_b64 |> EnigmaPq.hash() |> ReviewSignHash.from_binary()

      assert %{sign_hash: ^expected} =
               Shapes.Review.sync_derive_fields(%Review{sign_b64: sign_b64})
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert %{sign_hash: nil} = Shapes.Review.sync_derive_fields(%Review{sign_b64: nil})
    end
  end

  describe "ReviewPublicPasswords shape" do
    test "shape_name" do
      assert Shapes.ReviewPublicPasswords.shape_name() == :review_public_passwords
    end

    test "schema_module" do
      assert Shapes.ReviewPublicPasswords.schema_module() == ReviewPublicPassword
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert [{:user_card, "u_abc"}] =
               Shapes.ReviewPublicPasswords.sync_required_parents(:insert, %{author_hash: "u_abc"})
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      sign_b64 = :crypto.strong_rand_bytes(32)
      expected = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()

      assert %{sign_hash: ^expected} =
               Shapes.ReviewPublicPasswords.sync_derive_fields(%ReviewPublicPassword{
                 sign_b64: sign_b64
               })
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert %{sign_hash: nil} =
               Shapes.ReviewPublicPasswords.sync_derive_fields(%ReviewPublicPassword{
                 sign_b64: nil
               })
    end
  end

  describe "ReviewPostRight shape" do
    test "shape_name" do
      assert Shapes.ReviewPostRight.shape_name() == :review_post_right
    end

    test "schema_module" do
      assert Shapes.ReviewPostRight.schema_module() == ReviewPostRight
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert [{:user_card, "u_abc"}] =
               Shapes.ReviewPostRight.sync_required_parents(:insert, %{author_hash: "u_abc"})
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      sign_b64 = :crypto.strong_rand_bytes(32)
      expected = sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary()

      assert %{sign_hash: ^expected} =
               Shapes.ReviewPostRight.sync_derive_fields(%ReviewPostRight{sign_b64: sign_b64})
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert %{sign_hash: nil} =
               Shapes.ReviewPostRight.sync_derive_fields(%ReviewPostRight{sign_b64: nil})
    end
  end

  describe "ReviewRevokeRight shape" do
    test "shape_name" do
      assert Shapes.ReviewRevokeRight.shape_name() == :review_revoke_right
    end

    test "schema_module" do
      assert Shapes.ReviewRevokeRight.schema_module() == ReviewRevokeRight
    end

    test "sync_required_parents returns user_card dependency for author" do
      assert [{:user_card, "u_abc"}] =
               Shapes.ReviewRevokeRight.sync_required_parents(:insert, %{author_hash: "u_abc"})
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      sign_b64 = :crypto.strong_rand_bytes(32)
      expected = sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary()

      assert %{sign_hash: ^expected} =
               Shapes.ReviewRevokeRight.sync_derive_fields(%ReviewRevokeRight{sign_b64: sign_b64})
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert %{sign_hash: nil} =
               Shapes.ReviewRevokeRight.sync_derive_fields(%ReviewRevokeRight{sign_b64: nil})
    end
  end

  describe "ReviewList shape" do
    test "shape_name" do
      assert Shapes.ReviewList.shape_name() == :review_list
    end

    test "schema_module" do
      assert Shapes.ReviewList.schema_module() == ReviewList
    end

    test "sync_required_parents returns user_card dependency for list owner" do
      assert [{:user_card, "u_abc"}] =
               Shapes.ReviewList.sync_required_parents(:insert, %{user_hash: "u_abc"})
    end

    test "sync_derive_fields computes sign_hash from sign_b64" do
      sign_b64 = :crypto.strong_rand_bytes(32)
      expected = sign_b64 |> EnigmaPq.hash() |> ReviewListSignHash.from_binary()

      assert %{sign_hash: ^expected} =
               Shapes.ReviewList.sync_derive_fields(%ReviewList{sign_b64: sign_b64})
    end

    test "sync_derive_fields passes through when sign_b64 is nil" do
      assert %{sign_hash: nil} = Shapes.ReviewList.sync_derive_fields(%ReviewList{sign_b64: nil})
    end
  end

  describe "shape registry" do
    test "all five review shapes are registered" do
      names = Shapes.shape_names()

      for name <- [
            :review,
            :review_public_passwords,
            :review_post_right,
            :review_revoke_right,
            :review_list
          ] do
        assert name in names
      end
    end
  end
end
