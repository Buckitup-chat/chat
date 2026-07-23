defmodule Chat.Data.ReviewPasswordCandidate.Validation do
  @moduledoc "Validation for review password candidate ingest and promotion trigger."

  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPasswordCandidate.Promotion
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Data.User, as: UserData
  alias EnigmaPq
  alias Phoenix.Sync.Writer
  alias Phoenix.Sync.Writer.Operation

  def candidate_allowed(operation, %{challenge: challenge, signature: signature}) do
    author_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["author_hash"] || changes[:author_hash]

        _ ->
          nil
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(author_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def candidate_validate(candidate, changes, :insert) do
    candidate
    |> ReviewPasswordCandidate.create_changeset(changes)
    |> validate_review_and_author(changes)
  end

  def candidate_validate(_candidate, _changes, _op) do
    raise "password candidate updates not supported"
  end

  def candidate_post_apply_promote(multi, changeset, context) do
    Ecto.Multi.run(multi, Writer.operation_name(context, :promote), fn _repo, _changes ->
      case Ecto.Changeset.apply_action(changeset, :insert) do
        {:ok, candidate} -> try_promote(candidate)
        {:error, _} -> {:error, "candidate changeset invalid after insert"}
      end
    end)
  end

  defp try_promote(candidate) do
    with %{origin_hash: oh} <- ReviewData.get_review(candidate.review_hash),
         %{moderation_mode: mode} <- OriginData.get_origin(oh) do
      candidates = CandidateData.get_candidates_for_review(candidate.review_hash)

      pwd =
        Enum.find(
          candidates,
          &(&1.author_hash == candidate.author_hash and &1.password_b64 != nil)
        )

      null =
        Enum.find(
          candidates,
          &(&1.author_hash == candidate.author_hash and is_nil(&1.password_b64))
        )

      case {mode, pwd, null} do
        {_, nil, _} -> {:ok, :pending}
        {:none, pwd, _} -> Promotion.promote_candidate(pwd)
        {_, _pwd, nil} -> {:ok, :pending}
        {_, pwd, _null} -> Promotion.promote_candidate(pwd)
      end
    else
      _ -> {:error, "review or origin not found"}
    end
  end

  defp validate_review_and_author(changeset, changes) do
    review_hash = changes["review_hash"] || changes[:review_hash]
    author_hash = changes["author_hash"] || changes[:author_hash]

    case ReviewData.get_review(review_hash) do
      nil ->
        Ecto.Changeset.add_error(changeset, :review_hash, "review does not exist")

      %{author_hash: ^author_hash} ->
        changeset

      _ ->
        Ecto.Changeset.add_error(changeset, :author_hash, "author does not match review")
    end
  end
end
