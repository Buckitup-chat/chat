defmodule Chat.Data.Review do
  @moduledoc "Review context for managing public reviews in Postgres."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Review.Versioning
  alias Chat.Data.Schemas.Review

  def get_review(review_hash) do
    repo().get(Review, review_hash)
  end

  def upsert_review(changeset) do
    repo().insert(changeset,
      on_conflict: review_upsert_query(),
      conflict_target: :review_hash,
      allow_stale: true
    )
  end

  def insert_review_with_conflict(existing, new_review) do
    Versioning.handle_insert_with_conflict(repo(), existing, new_review)
  end

  def update_review_with_versioning(existing, new_review) do
    Versioning.handle_update_with_versioning(repo(), existing, new_review)
  end

  defp review_upsert_query do
    from(r in Review,
      update: [
        set: [
          content_b64: fragment("EXCLUDED.content_b64"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          parent_sign_hash: fragment("EXCLUDED.parent_sign_hash"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64"),
          sign_hash: fragment("EXCLUDED.sign_hash")
        ]
      ],
      where:
        is_nil(r.owner_timestamp) or
          r.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
