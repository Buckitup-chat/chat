defmodule Chat.Data.ReviewRevokeRight do
  @moduledoc "ReviewRevokeRight context for managing revoke rights in Postgres."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewRevokeRight

  def get_revoke_right(review_hash) do
    repo().get(ReviewRevokeRight, review_hash)
  end

  def upsert_revoke_right(changeset) do
    repo().insert(changeset,
      on_conflict: revoke_right_upsert_query(),
      conflict_target: :review_hash,
      allow_stale: true
    )
  end

  defp revoke_right_upsert_query do
    from(r in ReviewRevokeRight,
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
