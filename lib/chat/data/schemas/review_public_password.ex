defmodule Chat.Data.Schemas.ReviewPublicPassword do
  @moduledoc "Ecto schema for review_public_passwords. Controls public visibility of reviews."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key false

  @create_fields [
    :review_hash,
    :sign_hash,
    :origin_hash,
    :password_b64,
    :author_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64
  ]
  @create_required [
    :review_hash,
    :sign_hash,
    :origin_hash,
    :author_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64
  ]

  schema "review_public_passwords" do
    field(:review_hash, ReviewHash, primary_key: true)
    field(:sign_hash, ReviewPasswordSignHash, primary_key: true)
    field(:origin_hash, UserHash)
    field(:password_b64, :binary)
    field(:author_hash, UserHash)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(review_public_password, attrs) do
    review_public_password
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:review_hash, :sign_hash], name: :review_public_passwords_pkey)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(rp) do
      rp
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(rp), do: User.get_card(rp.author_hash).sign_pkey

    def signature(rp), do: rp.sign_b64
  end
end
