defmodule Chat.Data.Review.Versioning do
  @moduledoc """
  Handles versioning logic for review records.

  When a review is edited, the old version is archived to
  review_versions and the new version replaces it in review.

  Used by both peer sync (ShapeWriter) and HTTP ingestion (ElectricController).
  """

  import Ecto.Query

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewVersion
  alias Ecto.Multi

  @dialyzer {:no_opaque, archive_and_insert: 3, archive_and_update: 3}

  def handle_insert_with_conflict(repo, existing, new_review) do
    if new_review.owner_timestamp > existing.owner_timestamp do
      archive_and_insert(repo, existing, new_review)
    else
      archive_changeset(new_review)
      |> repo.insert(
        on_conflict: :nothing,
        conflict_target: [:review_hash, :sign_hash]
      )
    end
  end

  def handle_update_with_versioning(repo, existing, new_review) do
    if new_review.owner_timestamp > existing.owner_timestamp do
      archive_and_update(repo, existing, new_review)
    else
      archive_changeset(new_review)
      |> repo.insert(
        on_conflict: :nothing,
        conflict_target: [:review_hash, :sign_hash]
      )
    end
  end

  defp archive_and_insert(repo, existing, new_review) do
    Multi.new()
    |> archive_multi_insert(:archive, existing)
    |> Multi.insert(
      :update_main,
      Review.create_changeset(%Review{}, %{
        review_hash: new_review.review_hash,
        origin_hash: new_review.origin_hash,
        author_hash: new_review.author_hash,
        content_b64: new_review.content_b64,
        deleted_flag: new_review.deleted_flag,
        parent_sign_hash: existing.sign_hash,
        owner_timestamp: new_review.owner_timestamp,
        sign_b64: new_review.sign_b64,
        sign_hash: new_review.sign_hash
      }),
      on_conflict: review_upsert_query(),
      conflict_target: :review_hash,
      allow_stale: true
    )
    |> repo.transaction()
    |> case do
      {:ok, %{update_main: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp archive_and_update(repo, existing, new_review) do
    Multi.new()
    |> archive_multi_insert(:archive, existing)
    |> Multi.update(
      :update_main,
      Review.update_changeset(existing, %{
        content_b64: new_review.content_b64,
        deleted_flag: new_review.deleted_flag,
        parent_sign_hash: existing.sign_hash,
        owner_timestamp: new_review.owner_timestamp,
        sign_b64: new_review.sign_b64,
        sign_hash: new_review.sign_hash
      })
    )
    |> repo.transaction()
    |> case do
      {:ok, %{update_main: result}} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
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

  def archive_multi_insert(multi, name, review) do
    Multi.insert(multi, name, archive_changeset(review),
      on_conflict: :nothing,
      conflict_target: [:review_hash, :sign_hash],
      allow_stale: true
    )
  end

  @archive_fields [
    :review_hash,
    :sign_hash,
    :origin_hash,
    :author_hash,
    :content_b64,
    :deleted_flag,
    :parent_sign_hash,
    :owner_timestamp,
    :sign_b64
  ]

  def archive_changeset(review) do
    review
    |> Map.from_struct()
    |> Map.take(@archive_fields)
    |> then(&ReviewVersion.changeset(%ReviewVersion{}, &1))
  end
end
