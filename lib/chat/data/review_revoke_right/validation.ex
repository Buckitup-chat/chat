defmodule Chat.Data.ReviewRevokeRight.Validation do
  @moduledoc "Validation for review_revoke_right operations."

  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  # --- Peer sync validation ---

  # A right is created and signed by the review's author, so it must reference an
  # existing review and carry that review's author/origin. The insert is
  # intentionally unsigned (the signature is added by a later update), so we
  # cannot check a signature here — the cross-table binding is the guard.
  def validate_revoke_right_insert(right_struct) do
    %ReviewRevokeRight{}
    |> ReviewRevokeRight.create_changeset(Map.from_struct(right_struct))
    |> validate_matches_review(
      right_struct.review_hash,
      right_struct.author_hash,
      right_struct.origin_hash
    )
  end

  def validate_revoke_right_update(existing, right_struct) do
    attrs =
      right_struct
      |> Map.from_struct()
      |> Map.take([:deleted_flag, :owner_timestamp, :sign_b64, :sign_hash])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> ReviewRevokeRight.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- HTTP ingestion ---

  def revoke_right_allowed(operation, %{challenge: challenge, signature: signature}) do
    author_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["author_hash"] || changes[:author_hash]

        %Operation{operation: :update, data: %{"author_hash" => hash}} ->
          hash
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(author_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def revoke_right_validate(right, changes, op) do
    case op do
      :insert ->
        right
        |> ReviewRevokeRight.create_changeset(changes)
        |> validate_matches_review(
          changes["review_hash"] || changes[:review_hash],
          changes["author_hash"] || changes[:author_hash],
          changes["origin_hash"] || changes[:origin_hash]
        )

      :update ->
        right
        |> ReviewRevokeRight.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  # --- Cross-table binding ---

  defp validate_matches_review(changeset, review_hash, author_hash, origin_hash)
       when is_binary(review_hash) do
    case ReviewData.get_review(review_hash) do
      nil ->
        Ecto.Changeset.add_error(changeset, :review_hash, "review does not exist")

      review ->
        changeset
        |> check_matches(:author_hash, author_hash, review.author_hash)
        |> check_matches(:origin_hash, origin_hash, review.origin_hash)
    end
  end

  defp validate_matches_review(changeset, _review_hash, _author_hash, _origin_hash), do: changeset

  defp check_matches(changeset, _field, value, value), do: changeset

  defp check_matches(changeset, field, _value, _expected),
    do: Ecto.Changeset.add_error(changeset, field, "does not match review")
end
