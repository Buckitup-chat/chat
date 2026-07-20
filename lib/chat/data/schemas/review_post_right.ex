defmodule Chat.Data.Schemas.ReviewPostRight do
  @moduledoc "Ecto schema for review_post_right. KEM-encrypted envelope for publishing a review."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key {:review_hash, ReviewHash, []}

  @create_fields [
    :review_hash,
    :origin_hash,
    :author_hash,
    :kem_ciphertext_b64,
    :wrapped_row_b64,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required [
    :review_hash,
    :origin_hash,
    :author_hash,
    :kem_ciphertext_b64,
    :wrapped_row_b64,
    :deleted_flag,
    :owner_timestamp
  ]

  @update_fields [
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  schema "review_post_right" do
    field(:origin_hash, UserHash)
    field(:author_hash, UserHash)
    field(:kem_ciphertext_b64, :binary)
    field(:wrapped_row_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, ReviewPostRightSignHash)
  end

  def create_changeset(right, attrs) do
    right
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:review_hash, name: :review_post_right_pkey)
  end

  def update_changeset(right, attrs) do
    right
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(right) do
      right
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(right), do: User.get_card(right.author_hash).sign_pkey

    def signature(right), do: right.sign_b64
  end
end
