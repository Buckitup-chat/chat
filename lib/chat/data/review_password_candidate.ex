defmodule Chat.Data.ReviewPasswordCandidate do
  @moduledoc "ReviewPasswordCandidate context. Server-internal table for moderation pipeline."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewPasswordCandidate

  def get_candidate(review_hash, sign_hash) do
    repo().get_by(ReviewPasswordCandidate, review_hash: review_hash, sign_hash: sign_hash)
  end

  def get_candidates_for_review(review_hash) do
    ReviewPasswordCandidate
    |> where([c], c.review_hash == ^review_hash)
    |> order_by([c], asc: c.owner_timestamp)
    |> repo().all()
  end

  def insert_candidate(changeset) do
    repo().insert(changeset,
      on_conflict: :nothing,
      conflict_target: [:review_hash, :sign_hash],
      allow_stale: true
    )
  end
end
