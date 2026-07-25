defmodule Chat.Data.ReviewRightCandidate.Validation do
  @moduledoc "Validation for right candidate signature updates and completion trigger."

  alias Chat.Data.Integrity
  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias Chat.Data.User, as: UserData
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  def right_candidate_check(_operation), do: :ok

  def post_right_candidate_validate(candidate, changes, :update, pop_context) do
    validate_signature_update(candidate, changes, ReviewPostRightCandidate, pop_context)
  end

  def revoke_right_candidate_validate(candidate, changes, :update, pop_context) do
    validate_signature_update(candidate, changes, ReviewRevokeRightCandidate, pop_context)
  end

  def right_candidate_post_apply_complete(multi, changeset, context) do
    Ecto.Multi.run(multi, Writer.operation_name(context, :complete), fn _repo, _changes ->
      review_hash = Ecto.Changeset.get_field(changeset, :review_hash)
      try_complete(review_hash)
    end)
  end

  defp try_complete(review_hash) do
    with %{origin_hash: oh} <- ReviewData.get_review(review_hash),
         %{moderation_mode: mode} <- OriginData.get_origin(oh) do
      case mode do
        :post ->
          case RightCandidateData.get_revoke_candidate(review_hash) do
            %{sign_b64: sign} when not is_nil(sign) -> Promotion.complete_promotion(review_hash)
            _ -> {:ok, :pending}
          end

        :pre ->
          post_c = RightCandidateData.get_post_candidate(review_hash)
          revoke_c = RightCandidateData.get_revoke_candidate(review_hash)

          if post_c && post_c.sign_b64 && revoke_c && revoke_c.sign_b64 do
            Promotion.complete_promotion(review_hash)
          else
            {:ok, :pending}
          end

        :none ->
          {:ok, :not_applicable}
      end
    else
      _ -> {:ok, :pending}
    end
  end

  defp validate_signature_update(candidate, changes, schema, pop_context) do
    changeset = schema.sign_changeset(candidate, changes)

    with {:pop, :ok} <- {:pop, verify_pop(candidate.author_hash, pop_context)},
         {:sig, :ok} <- {:sig, verify_candidate_signature(changeset, candidate)} do
      changeset
    else
      {:pop, _} ->
        Ecto.Changeset.add_error(changeset, :sign_b64, "PoP verification failed")

      {:sig, _} ->
        Ecto.Changeset.add_error(changeset, :sign_b64, "invalid signature")
    end
  end

  defp verify_pop(author_hash, %{challenge: challenge, signature: signature}) do
    case UserData.get_card(author_hash) do
      %{sign_pkey: sign_pkey} ->
        if EnigmaPq.verify(challenge, signature, sign_pkey), do: :ok, else: :error

      _ ->
        :error
    end
  end

  defp verify_candidate_signature(changeset, existing) do
    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, signed} ->
        merged = %{existing | sign_b64: signed.sign_b64, sign_hash: signed.sign_hash}
        Integrity.verify_signature(merged)

      {:error, _} ->
        {:error, :invalid_changeset}
    end
  end
end
