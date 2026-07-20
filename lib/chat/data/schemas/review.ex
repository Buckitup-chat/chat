defmodule Chat.Data.Schemas.Review do
  @moduledoc "Ecto schema for public reviews on origins."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key {:review_hash, ReviewHash, []}

  @create_fields [
    :review_hash,
    :origin_hash,
    :author_hash,
    :content_b64,
    :deleted_flag,
    :parent_sign_hash,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required [
    :review_hash,
    :origin_hash,
    :author_hash,
    :content_b64,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  @update_fields [
    :content_b64,
    :deleted_flag,
    :parent_sign_hash,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @update_required [
    :content_b64,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  schema "review" do
    field(:origin_hash, UserHash)
    field(:author_hash, UserHash)
    field(:content_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:parent_sign_hash, ReviewSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, ReviewSignHash)
  end

  def create_changeset(review, attrs) do
    review
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:review_hash, name: :review_pkey)
  end

  def update_changeset(review, attrs) do
    review
    |> cast(attrs, @update_fields)
    |> validate_required(@update_required)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(review) do
      review
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(review), do: User.get_card(review.author_hash).sign_pkey

    def signature(review), do: review.sign_b64
  end
end
