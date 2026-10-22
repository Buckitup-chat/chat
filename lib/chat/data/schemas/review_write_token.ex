defmodule Chat.Data.Schemas.ReviewWriteToken do
  @moduledoc "Ecto schema for review_write_tokens. Tracks token lifecycle (pending -> bound -> reviewed -> soft-deleted)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.OriginOrderHash
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key false

  @create_fields [
    :nonce,
    :origin_hash,
    :review_bot_hash,
    :origin_order_hash,
    :parent_nonce,
    :user_hash,
    :review_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required [
    :nonce,
    :origin_hash,
    :review_bot_hash,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  @update_fields [
    :user_hash,
    :review_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @update_required [:owner_timestamp, :sign_b64, :sign_hash]

  schema "review_write_tokens" do
    field(:nonce, :string, primary_key: true)
    field(:origin_hash, UserHash)
    field(:review_bot_hash, UserHash)
    field(:origin_order_hash, OriginOrderHash)
    field(:parent_nonce, :string)
    field(:user_hash, UserHash)
    field(:review_hash, ReviewHash)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, ReviewWriteTokenSignHash)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:nonce, name: :review_write_tokens_pkey)
  end

  def update_changeset(token, attrs) do
    token
    |> cast(attrs, @update_fields)
    |> validate_required(@update_required)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(token) do
      token
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(token), do: User.get_card(token.review_bot_hash).sign_pkey

    def signature(token), do: token.sign_b64
  end
end
