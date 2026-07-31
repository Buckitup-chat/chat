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

  def delete_stale_candidates(max_age_seconds) do
    delete_stale(ReviewPostRightCandidate, max_age_seconds)
    delete_stale(ReviewRevokeRightCandidate, max_age_seconds)
  end

  defp delete_stale(schema, max_age_seconds) do
    max_per_user =
      from(c in schema,
        group_by: c.author_hash,
        select: {c.author_hash, max(c.owner_timestamp)}
      )
      |> repo().all()

    Enum.reduce(max_per_user, {0, nil}, fn {author_hash, max_ts}, {total, _} ->
      cutoff = max_ts - max_age_seconds

      {deleted, _} =
        schema
        |> where([c], c.author_hash == ^author_hash and c.owner_timestamp < ^cutoff)
        |> repo().delete_all()

      {total + deleted, nil}
    end)
  end
end
