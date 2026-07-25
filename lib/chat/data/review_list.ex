defmodule Chat.Data.ReviewList do
  @moduledoc "ReviewList context for managing per-user review lists in Postgres."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewList

  def get_review_list_entry(user_hash, review_hash) do
    repo().get_by(ReviewList, user_hash: user_hash, review_hash: review_hash)
  end

  def get_review_list_for_user(user_hash) do
    ReviewList
    |> where([rl], rl.user_hash == ^user_hash)
    |> repo().all()
  end

  def upsert_review_list_entry(changeset) do
    repo().insert(changeset,
      on_conflict: review_list_upsert_query(),
      conflict_target: [:user_hash, :review_hash],
      allow_stale: true
    )
  end

  defp review_list_upsert_query do
    from(rl in ReviewList,
      update: [
        set: [
          password_b64: fragment("EXCLUDED.password_b64"),
          review_password_sign_hash: fragment("EXCLUDED.review_password_sign_hash"),
          post_right_sign_hash: fragment("EXCLUDED.post_right_sign_hash"),
          revoke_right_sign_hash: fragment("EXCLUDED.revoke_right_sign_hash"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64"),
          sign_hash: fragment("EXCLUDED.sign_hash")
        ]
      ],
      where:
        is_nil(rl.owner_timestamp) or
          rl.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
