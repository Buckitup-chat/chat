defmodule Chat.Data.Schemas.DialogKey do
  @moduledoc """
  Ecto schema for dialog key exchange rows. One row per participant per dialog.

  Spec: `docs/pq/reqs/pq_dialogs.done.md` §1 `dialog_keys`.
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
    |> validate_dialog_hash_matches_pair()
    |> unique_constraint([:dialog_hash, :sender_hash], name: :dialog_keys_pkey)
  end

  def update_changeset(dialog_key, attrs) do
    dialog_key
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
  end

  # A key row is bound to the dialog of its (sender, peer) pair; it cannot be
  # lifted into another dialog.
  defp validate_dialog_hash_matches_pair(changeset) do
    with dialog_hash when is_binary(dialog_hash) <- get_field(changeset, :dialog_hash),
         sender_hash when is_binary(sender_hash) <- get_field(changeset, :sender_hash),
         peer_hash when is_binary(peer_hash) <- get_field(changeset, :peer_hash),
         false <- dialog_hash == DialogHash.for_pair(sender_hash, peer_hash) do
      add_error(changeset, :dialog_hash, "does not match sender/peer pair")
    else
      _ -> changeset
    end
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
