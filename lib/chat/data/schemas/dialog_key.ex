defmodule Chat.Data.Schemas.DialogKey do
  @moduledoc """
  Ecto schema for dialog key exchange rows. One row per participant per dialog.

  Spec: `docs/reqs/pq_dialogs.md` §1 `dialog_keys`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.UserHash

  @primary_key false

  @create_fields [
    :dialog_hash,
    :sender_hash,
    :peer_hash,
    :peer_kem_wrap_key_b64,
    :peer_wrapped_msg_key_b64,
    :owner_timestamp,
    :deleted_flag,
    :sign_b64
  ]
  @create_required @create_fields
  @update_fields [
    :peer_kem_wrap_key_b64,
    :peer_wrapped_msg_key_b64,
    :owner_timestamp,
    :deleted_flag,
    :sign_b64
  ]

  schema "dialog_keys" do
    field(:dialog_hash, DialogHash, primary_key: true)
    field(:sender_hash, UserHash, primary_key: true)
    field(:peer_hash, UserHash)
    field(:peer_kem_wrap_key_b64, :binary)
    field(:peer_wrapped_msg_key_b64, :binary)
    field(:owner_timestamp, :integer)
    field(:deleted_flag, :boolean, default: false)
    field(:sign_b64, :binary)
  end

  def create_changeset(dialog_key, attrs) do
    dialog_key
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:dialog_hash, :sender_hash], name: :dialog_keys_pkey)
  end

  def update_changeset(dialog_key, attrs) do
    dialog_key
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(dialog_key) do
      dialog_key
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(dialog_key), do: User.get_card(dialog_key.sender_hash).sign_pkey

    def signature(dialog_key), do: dialog_key.sign_b64
  end
end
