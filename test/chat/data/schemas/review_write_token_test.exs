defmodule Chat.Data.Schemas.ReviewWriteTokenTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.Schemas.ReviewWriteToken

  @valid_nonce_hash "rwn_" <> String.duplicate("12", 64)
  @valid_user_hash "u_" <> String.duplicate("ab", 64)
  @valid_bot_hash "u_" <> String.duplicate("cd", 64)
  @valid_sign_hash "rwt_" <> String.duplicate("ef", 64)

  @valid_attrs %{
    nonce_hash: @valid_nonce_hash,
    nonce_enc_b64: :crypto.strong_rand_bytes(60),
    origin_hash: @valid_user_hash,
    review_bot_hash: @valid_bot_hash,
    deleted_flag: false,
    owner_timestamp: 1_000_000,
    sign_b64: :crypto.strong_rand_bytes(64),
    sign_hash: @valid_sign_hash
  }

  describe "create_changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = ReviewWriteToken.create_changeset(%ReviewWriteToken{}, @valid_attrs)
      assert changeset.valid?
    end

    test "accepts nullable fields as nil" do
      changeset =
        ReviewWriteToken.create_changeset(
          %ReviewWriteToken{},
          Map.merge(@valid_attrs, %{
            origin_order_hash: nil,
            parent_nonce_hash: nil,
            user_hash: nil,
            review_hash: nil
          })
        )

      assert changeset.valid?
    end

    test "requires mandatory fields" do
      changeset = ReviewWriteToken.create_changeset(%ReviewWriteToken{}, %{})
      refute changeset.valid?

      for field <- [
            :nonce_hash,
            :nonce_enc_b64,
            :origin_hash,
            :review_bot_hash,
            :owner_timestamp,
            :sign_b64,
            :sign_hash
          ] do
        assert Keyword.has_key?(changeset.errors, field), "expected error on #{field}"
      end
    end
  end

  describe "update_changeset/2" do
    test "valid update attrs produce a valid changeset" do
      existing = struct(ReviewWriteToken, @valid_attrs)

      changeset =
        ReviewWriteToken.update_changeset(existing, %{
          deleted_flag: true,
          owner_timestamp: 2_000_000,
          sign_b64: :crypto.strong_rand_bytes(64),
          sign_hash: @valid_sign_hash
        })

      assert changeset.valid?
    end

    test "ignores nonce_hash and nonce_enc_b64 changes" do
      existing = struct(ReviewWriteToken, @valid_attrs)

      changeset =
        ReviewWriteToken.update_changeset(existing, %{
          nonce_hash: "rwn_" <> String.duplicate("34", 64),
          nonce_enc_b64: :crypto.strong_rand_bytes(60),
          owner_timestamp: 2_000_000,
          sign_b64: :crypto.strong_rand_bytes(64),
          sign_hash: @valid_sign_hash
        })

      refute Map.has_key?(changeset.changes, :nonce_hash)
      refute Map.has_key?(changeset.changes, :nonce_enc_b64)
    end

    test "requires update fields" do
      existing = struct(ReviewWriteToken, @valid_attrs)

      changeset =
        ReviewWriteToken.update_changeset(existing, %{
          owner_timestamp: nil,
          sign_b64: nil,
          sign_hash: nil
        })

      refute changeset.valid?

      for field <- [:owner_timestamp, :sign_b64, :sign_hash] do
        assert Keyword.has_key?(changeset.errors, field), "expected error on #{field}"
      end
    end
  end
end
