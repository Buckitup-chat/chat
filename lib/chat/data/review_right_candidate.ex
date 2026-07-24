defmodule Chat.Data.ReviewRightCandidate do
  @moduledoc "Data context for review right candidates (post + revoke). Server-internal staging."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate

  def get_post_candidate(review_hash) do
    repo().get(ReviewPostRightCandidate, review_hash)
  end

  def get_revoke_candidate(review_hash) do
    repo().get(ReviewRevokeRightCandidate, review_hash)
  end

  def insert_post_candidate(changeset) do
    repo().insert(changeset,
      on_conflict: :nothing,
      conflict_target: :review_hash,
      allow_stale: true
    )
  end

  def insert_revoke_candidate(changeset) do
    repo().insert(changeset,
      on_conflict: :nothing,
      conflict_target: :review_hash,
      allow_stale: true
    )
  end

  def update_candidate(candidate, attrs) do
    candidate
    |> candidate.__struct__.sign_changeset(attrs)
    |> repo().update()
  end

  def delete_candidates_for_review(review_hash) do
    ReviewPostRightCandidate
    |> where([c], c.review_hash == ^review_hash)
    |> repo().delete_all()

    ReviewRevokeRightCandidate
    |> where([c], c.review_hash == ^review_hash)
    |> repo().delete_all()
  end

  def delete_stale_candidates(max_age_ms) do
    cutoff = System.os_time(:millisecond) - max_age_ms

    ReviewPostRightCandidate
    |> where([c], c.inserted_at < ^cutoff)
    |> repo().delete_all()

    ReviewRevokeRightCandidate
    |> where([c], c.inserted_at < ^cutoff)
    |> repo().delete_all()
  end
end
