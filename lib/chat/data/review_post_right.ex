defmodule Chat.Data.ReviewPostRight do
  @moduledoc "ReviewPostRight context for managing post rights in Postgres."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewPostRight

  def get_post_right(review_hash) do
    repo().get(ReviewPostRight, review_hash)
  end

  def upsert_post_right(changeset) do
    repo().insert(changeset,
      on_conflict: post_right_upsert_query(),
      conflict_target: :review_hash,
      allow_stale: true
    )
  end

  defp post_right_upsert_query do
    from(r in ReviewPostRight,
      update: [
        set: [
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
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
