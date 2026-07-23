defmodule Chat.Data.ReviewPublicPassword.Validation do
  @moduledoc "Signature and integrity validation for review_public_passwords operations."

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq

  # --- Peer sync validation ---

  def validate_review_public_password_insert(rp_struct) do
    %ReviewPublicPassword{}
    |> ReviewPublicPassword.create_changeset(Map.from_struct(rp_struct))
    |> UserValidation.validate_signature()
    |> validate_matches_review()
  end

  # --- HTTP ingestion ---

  def moderate_check(operation, %{challenge: challenge, signature: signature}) do
    origin_hash = operation.changes["origin_hash"] || operation.changes[:origin_hash]

    with %{sign_pkey: sign_pkey} <- UserData.get_card(origin_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "not authorized as origin identity"}
    end
  end

  def validate_origin_moderate(rp_struct, changes, :insert) do
    rp_struct
    |> ReviewPublicPassword.create_changeset(changes)
    |> UserValidation.validate_signature()
    |> validate_matches_review()
  end

  # --- Private ---

  defp validate_matches_review(changeset) do
    review_hash = Ecto.Changeset.get_field(changeset, :review_hash)

    if review_hash do
      case ReviewData.get_review(review_hash) do
        nil ->
          Ecto.Changeset.add_error(changeset, :review_hash, "review does not exist")

        review ->
          changeset
          |> check_matches(
            :author_hash,
            Ecto.Changeset.get_field(changeset, :author_hash),
            review.author_hash
          )
          |> check_matches(
            :origin_hash,
            Ecto.Changeset.get_field(changeset, :origin_hash),
            review.origin_hash
          )
      end
    else
      changeset
    end
  end

  defp check_matches(changeset, _field, value, value), do: changeset

  defp check_matches(changeset, field, _value, _expected),
    do: Ecto.Changeset.add_error(changeset, field, "does not match review")
end
