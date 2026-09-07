defmodule Chat.Data.Schemas.ReviewVersion do
  @moduledoc """
  Ecto schema for archived versions of reviews.

  Spec: `docs/pq/reqs/reviews/pq_review_versioning.in_progress.md` §review_versions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.Types.UserHash

  @primary_key false

  schema "review_versions" do
    field(:review_hash, ReviewHash, primary_key: true)
    field(:sign_hash, ReviewSignHash, primary_key: true)
    field(:origin_hash, UserHash)
    field(:author_hash, UserHash)
    field(:content_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:parent_sign_hash, ReviewSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :review_hash,
      :sign_hash,
      :origin_hash,
      :author_hash,
      :content_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64
    ])
    |> validate_required([
      :review_hash,
      :sign_hash,
      :origin_hash,
      :author_hash,
      :content_b64,
      :deleted_flag,
      :owner_timestamp,
      :sign_b64
    ])
    |> unique_constraint([:review_hash, :sign_hash],
      name: :review_versions_pkey
    )
  end
end
