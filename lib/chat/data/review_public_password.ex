defmodule Chat.Data.ReviewPublicPassword do
  @moduledoc "ReviewPublicPassword context for managing review visibility in Postgres."

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.ReviewPublicPassword

  def get_review_public_password(review_hash, sign_hash) do
    repo().get_by(ReviewPublicPassword, review_hash: review_hash, sign_hash: sign_hash)
  end

  def get_latest_for_review(review_hash) do
    ReviewPublicPassword
    |> where([rp], rp.review_hash == ^review_hash)
    |> order_by([rp], desc: rp.owner_timestamp)
    |> limit(1)
    |> repo().one()
  end

  def upsert_review_public_password(changeset) do
    repo().insert(changeset,
      on_conflict: review_public_password_upsert_query(),
      conflict_target: [:review_hash, :sign_hash],
      allow_stale: true
    )
  end

  defp review_public_password_upsert_query do
    from(rp in ReviewPublicPassword,
      update: [
        set: [
          password_b64: fragment("EXCLUDED.password_b64"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64")
        ]
      ],
      where:
        is_nil(rp.owner_timestamp) or
          rp.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
