defmodule Chat.Data.Schemas.VouchToken do
  @moduledoc "Ecto schema for vouch_tokens. Signed trust attestation scoped to a dot-path resource."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key false

  @create_fields [
    :kind,
    :issuer_hash,
    :subject_hash,
    :owner_timestamp,
    :deleted_flag,
    :sign_b64
  ]
  @create_required @create_fields

  @update_fields [
    :deleted_flag,
    :owner_timestamp,
    :sign_b64
  ]
  @update_required @update_fields

  schema "vouch_tokens" do
    field(:kind, :string, primary_key: true)
    field(:issuer_hash, UserHash, primary_key: true)
    field(:subject_hash, UserHash, primary_key: true)
    field(:owner_timestamp, :integer)
    field(:deleted_flag, :boolean, default: false)
    field(:sign_b64, :binary)
  end

  def create_changeset(vouch_token, attrs) do
    vouch_token
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:kind, :issuer_hash, :subject_hash], name: :vouch_tokens_pkey)
  end

  def update_changeset(vouch_token, attrs) do
    vouch_token
    |> cast(attrs, @update_fields)
    |> validate_required(@update_required)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(vt) do
      vt
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(vt), do: User.get_card(vt.issuer_hash).sign_pkey

    def signature(vt), do: vt.sign_b64
  end
end
