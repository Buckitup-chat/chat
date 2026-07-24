defmodule Chat.Data.Schemas.ReviewList do
  @moduledoc "Ecto schema for review_list. Per-user encrypted list of review passwords for contacts."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key false

  @create_fields [
    :user_hash,
    :review_hash,
    :password_b64,
    :review_password_sign_hash,
    :post_right_sign_hash,
    :revoke_right_sign_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required [
    :user_hash,
    :review_hash,
    :password_b64,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  @update_fields [
    :password_b64,
    :review_password_sign_hash,
    :post_right_sign_hash,
    :revoke_right_sign_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @update_required [
    :password_b64,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  schema "review_list" do
    field(:user_hash, UserHash, primary_key: true)
    field(:review_hash, ReviewHash, primary_key: true)
    field(:password_b64, :binary)
    field(:review_password_sign_hash, ReviewPasswordSignHash)
    field(:post_right_sign_hash, ReviewPostRightSignHash)
    field(:revoke_right_sign_hash, ReviewRevokeRightSignHash)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, ReviewListSignHash)
  end

  def create_changeset(review_list, attrs) do
    review_list
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:user_hash, :review_hash], name: :review_list_pkey)
  end

  def update_changeset(review_list, attrs) do
    review_list
    |> cast(attrs, @update_fields)
    |> validate_required(@update_required)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(rl) do
      rl
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(rl), do: User.get_card(rl.user_hash).sign_pkey

    def signature(rl), do: rl.sign_b64
  end
end
