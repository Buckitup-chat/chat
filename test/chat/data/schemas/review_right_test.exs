defmodule Chat.Data.Schemas.ReviewRightTest do
  @moduledoc """
  `Chat.Data.Schemas.ReviewRight` is a `__using__` macro: the expansion is
  checked directly (cover cannot see the compile-time expansion of the real
  schemas) and its generated changesets and protocol impls are exercised
  through `ReviewPostRight` and `ReviewRevokeRight`.
  """
  use ExUnit.Case, async: true

  require Chat.Data.Schemas.ReviewRight

  import Chat.Test.ReviewFixtures, only: [random_review_hash: 0]

  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Schemas.ReviewRight
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User.Validation.TimestampedData

  @required ~W(review_hash origin_hash author_hash kem_ciphertext_b64 wrapped_row_b64 owner_timestamp)a

  describe "__using__/1 expansion" do
    test "derives table, pkey constraint and sign hash type from the kind" do
      code = expand(kind: :post)

      assert code =~ ~S[schema("review_post_right")]
      assert code =~ ~S(name: "review_post_right_pkey")
      assert code =~ "alias Chat.Data.Types.ReviewPostRightSignHash"
    end

    test "uses the revoke names for kind: :revoke" do
      code = expand(kind: :revoke)

      assert code =~ ~S[schema("review_revoke_right")]
      assert code =~ "alias Chat.Data.Types.ReviewRevokeRightSignHash"
    end

    test "requires the kind option" do
      assert_raise KeyError, fn -> expand([]) end
    end
  end

  describe "create_changeset/2" do
    test "accepts a complete right" do
      assert %{valid?: true} = ReviewPostRight.create_changeset(%ReviewPostRight{}, attrs())
    end

    test "requires every create field" do
      %{errors: errors} = ReviewRevokeRight.create_changeset(%ReviewRevokeRight{}, %{})

      assert errors |> Keyword.keys() |> Enum.sort() == Enum.sort(@required)
    end
  end

  describe "update_changeset/2" do
    test "requires the signature fields" do
      %{valid?: false, errors: errors} =
        ReviewPostRight.update_changeset(%ReviewPostRight{}, %{deleted_flag: true})

      assert errors |> Keyword.keys() |> Enum.sort() == [:owner_timestamp, :sign_b64, :sign_hash]
    end
  end

  describe "protocol impls" do
    test "TimestampedData reads the owner timestamp" do
      assert TimestampedData.existing_timestamp(%ReviewPostRight{owner_timestamp: 42}) == 42
    end

    test "Signable signs everything except the signature" do
      right = struct(ReviewRevokeRight, Map.put(attrs(), :sign_b64, "sig"))

      fields = Signable.signable_fields(right)

      refute Map.has_key?(fields, :sign_b64)
      refute Map.has_key?(fields, :sign_hash)
      refute Map.has_key?(fields, :__meta__)
      assert fields.wrapped_row_b64 == "row"
      assert Signable.signature(right) == "sig"
    end
  end

  # Helpers

  defp expand(opts) do
    quote do
      ReviewRight.__using__(unquote(opts))
    end
    |> Macro.expand_once(__ENV__)
    |> Macro.to_string()
  end

  defp attrs do
    %{
      review_hash: random_review_hash(),
      origin_hash: random_user_hash(),
      author_hash: random_user_hash(),
      kem_ciphertext_b64: "kem",
      wrapped_row_b64: "row",
      deleted_flag: false,
      owner_timestamp: 1
    }
  end

  defp random_user_hash, do: 64 |> :crypto.strong_rand_bytes() |> UserHash.from_binary()
end
