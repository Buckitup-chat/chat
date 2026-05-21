defmodule Chat.Data.Schemas.DialogMessage do
  @moduledoc """
  Ecto schema for dialog message tips. Current version of each message.

  Spec: `docs/reqs/pq_dialogs.md` §2 `dialog_messages`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.Types.UserHash

  @primary_key {:message_id, DialogMessageId, []}
  @max_blob_size 1_048_576

  @create_fields [
    :message_id,
    :dialog_hash,
    :sender_hash,
    :content_b64,
    :deleted_flag,
    :refs_map_b64,
    :parent_sign_hash,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required [
    :message_id,
    :dialog_hash,
    :sender_hash,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @update_fields [
    :content_b64,
    :deleted_flag,
    :refs_map_b64,
    :parent_sign_hash,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]

  schema "dialog_messages" do
    field(:dialog_hash, DialogHash)
    field(:sender_hash, UserHash)
    field(:content_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:refs_map_b64, :binary)
    field(:parent_sign_hash, DialogMessageSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, DialogMessageSignHash)
  end

  def create_changeset(message, attrs) do
    message
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> validate_blob_size(:content_b64)
    |> validate_blob_size(:refs_map_b64)
    |> unique_constraint(:message_id, name: :dialog_messages_pkey)
  end

  def update_changeset(message, attrs) do
    message
    |> cast(attrs, @update_fields)
    |> validate_required([:owner_timestamp, :sign_b64, :sign_hash])
    |> validate_blob_size(:content_b64)
    |> validate_blob_size(:refs_map_b64)
  end

  defp validate_blob_size(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      value when byte_size(value) <= @max_blob_size -> changeset
      _ -> add_error(changeset, field, "exceeds 1 MB limit")
    end
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(message) do
      message
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(message), do: User.get_card(message.sender_hash).sign_pkey

    def signature(message), do: message.sign_b64
  end
end
