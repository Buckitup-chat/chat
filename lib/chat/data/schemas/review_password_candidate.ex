defmodule Chat.Data.Schemas.ReviewPasswordCandidate do
  @moduledoc "Ecto schema for review_password_candidate. Server-internal, not synced via Electric."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.UserHash

  @primary_key false

  @create_fields [
    :review_hash,
    :sign_hash,
    :origin_hash,
    :password_b64,
    :author_hash,
    :owner_timestamp,
    :sign_b64
  ]
  @create_required [
    :review_hash,
    :sign_hash,
    :origin_hash,
    :author_hash,
    :owner_timestamp,
    :sign_b64
  ]

  schema "review_password_candidate" do
    field(:review_hash, ReviewHash, primary_key: true)
    field(:sign_hash, ReviewPasswordSignHash, primary_key: true)
    field(:origin_hash, UserHash)
    field(:password_b64, :binary)
    field(:author_hash, UserHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:review_hash, :sign_hash], name: :review_password_candidate_pkey)
  end
end
