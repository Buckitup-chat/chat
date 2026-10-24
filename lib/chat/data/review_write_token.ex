defmodule Chat.Data.ReviewWriteToken do
  @moduledoc "Data access for review_write_tokens."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewWriteToken

  def get_review_write_token(nonce) do
    repo().get(ReviewWriteToken, nonce)
  end

  def pending_expired_tokens(origin_hash, threshold_ts) do
    from(rwt in ReviewWriteToken,
      where:
        rwt.origin_hash == ^origin_hash and
          is_nil(rwt.user_hash) and
          rwt.deleted_flag == false and
          rwt.owner_timestamp < ^threshold_ts
    )
    |> repo().all()
  end

  def hard_delete_old_tombstones(threshold_ts) do
    from(rwt in ReviewWriteToken,
      where: rwt.deleted_flag == true and rwt.owner_timestamp < ^threshold_ts
    )
    |> repo().delete_all()
  end

  def link_to_review(repo, nonce, review_hash) do
    from(rwt in ReviewWriteToken,
      where: rwt.nonce == ^nonce and is_nil(rwt.review_hash)
    )
    |> repo.update_all(set: [review_hash: review_hash])
  end

  def upsert_review_write_token(changeset) do
    repo().insert(changeset,
      on_conflict: review_write_token_upsert_query(),
      conflict_target: :nonce,
      allow_stale: true
    )
  end

  defp review_write_token_upsert_query do
    from(rwt in ReviewWriteToken,
      update: [
        set: [
          user_hash: fragment("EXCLUDED.user_hash"),
          review_hash: fragment("EXCLUDED.review_hash"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64"),
          sign_hash: fragment("EXCLUDED.sign_hash")
        ]
      ],
      where:
        is_nil(rwt.owner_timestamp) or
          rwt.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
