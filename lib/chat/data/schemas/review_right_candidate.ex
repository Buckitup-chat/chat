defmodule Chat.Data.Schemas.ReviewPostRightCandidate do
  @moduledoc "Server-internal staging for unsigned post rights. Mirrors ReviewPostRight."

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
    :inserted_at
  ]
  @create_required @create_fields

  @sign_fields [:sign_b64, :sign_hash]

  schema "review_post_right_candidate" do
    field(:origin_hash, UserHash)
    field(:author_hash, UserHash)
    field(:kem_ciphertext_b64, :binary)
    field(:wrapped_row_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, ReviewPostRightSignHash)
    field(:inserted_at, :integer)
  end

  def create_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:review_hash, name: :review_post_right_candidate_pkey)
  end

  def sign_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @sign_fields)
    |> validate_required(@sign_fields)
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(rc) do
      rc
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :inserted_at, :__meta__])
    end

    def signing_key(rc), do: User.get_card(rc.author_hash).sign_pkey

    def signature(rc), do: rc.sign_b64
  end
end

defmodule Chat.Data.Schemas.ReviewRevokeRightCandidate do
  @moduledoc "Server-internal staging for unsigned revoke rights. Mirrors ReviewRevokeRight."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
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
    :inserted_at
  ]
  @create_required @create_fields

  @sign_fields [:sign_b64, :sign_hash]

  schema "review_revoke_right_candidate" do
    field(:origin_hash, UserHash)
    field(:author_hash, UserHash)
    field(:kem_ciphertext_b64, :binary)
    field(:wrapped_row_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, ReviewRevokeRightSignHash)
    field(:inserted_at, :integer)
  end

  def create_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:review_hash, name: :review_revoke_right_candidate_pkey)
  end

  def sign_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @sign_fields)
    |> validate_required(@sign_fields)
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(rc) do
      rc
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :inserted_at, :__meta__])
    end

    def signing_key(rc), do: User.get_card(rc.author_hash).sign_pkey

    def signature(rc), do: rc.sign_b64
  end
end
