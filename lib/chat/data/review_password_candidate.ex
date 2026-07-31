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

  def delete_stale_candidates(max_age_seconds) do
    max_per_user =
      from(c in ReviewPasswordCandidate,
        group_by: c.author_hash,
        select: {c.author_hash, max(c.owner_timestamp)}
      )
      |> repo().all()

    Enum.reduce(max_per_user, {0, nil}, fn {author_hash, max_ts}, {total, _} ->
      cutoff = max_ts - max_age_seconds

      {deleted, _} =
        ReviewPasswordCandidate
        |> where([c], c.author_hash == ^author_hash and c.owner_timestamp < ^cutoff)
        |> repo().delete_all()

      {total + deleted, nil}
    end)
  end
end
