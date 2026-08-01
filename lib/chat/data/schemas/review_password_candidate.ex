defmodule Chat.Data.Schemas.ReviewPasswordCandidate do
  @moduledoc "Ecto schema for review_password_candidate. Server-internal, not synced via Electric."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Schemas.ReviewPublicPassword
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

  @doc """
  Projects a candidate onto the `review_public_passwords` row it will be promoted
  into (`deleted_flag: false`).

  The author signs that target row, never the candidate itself, so every
  signature check on a candidate has to go through this projection.
  """
  def to_public_password(candidate) do
    %ReviewPublicPassword{
      review_hash: candidate.review_hash,
      sign_hash: candidate.sign_hash,
      origin_hash: candidate.origin_hash,
      password_b64: candidate.password_b64,
      author_hash: candidate.author_hash,
      deleted_flag: false,
      owner_timestamp: candidate.owner_timestamp,
      sign_b64: candidate.sign_b64
    }
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.Integrity.Signable
    alias Chat.Data.Schemas.ReviewPasswordCandidate

    def signable_fields(candidate) do
      candidate
      |> ReviewPasswordCandidate.to_public_password()
      |> Signable.signable_fields()
    end

    def signing_key(candidate), do: User.get_card(candidate.author_hash).sign_pkey

    def signature(candidate), do: candidate.sign_b64
  end
end
