defmodule Chat.Data.ReviewPublicPassword.Validation do
  @moduledoc "Signature and integrity validation for review_public_passwords operations."

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.User.Validation, as: UserValidation

  def validate_review_public_password_insert(rp_struct) do
    %ReviewPublicPassword{}
    |> ReviewPublicPassword.create_changeset(Map.from_struct(rp_struct))
    |> UserValidation.validate_signature()
    |> validate_matches_review(rp_struct)
  end

  # A review_public_passwords row is the "proof of promotion" that review_list
  # relies on, so it must belong to the review it points at: the row's author
  # and origin have to match the review's own author and origin. Otherwise any
  # identity could mint a promotion record for someone else's review.
  defp validate_matches_review(changeset, %{review_hash: review_hash} = rp)
       when is_binary(review_hash) do
    case ReviewData.get_review(review_hash) do
      nil ->
        Ecto.Changeset.add_error(changeset, :review_hash, "review does not exist")

      review ->
        changeset
        |> check_matches(:author_hash, rp.author_hash, review.author_hash)
        |> check_matches(:origin_hash, rp.origin_hash, review.origin_hash)
    end
  end

  defp validate_matches_review(changeset, _rp), do: changeset

  defp check_matches(changeset, _field, value, value), do: changeset

  defp check_matches(changeset, field, _value, _expected),
    do: Ecto.Changeset.add_error(changeset, field, "does not match review")
end
