defmodule Chat.Data.Schemas.DialogMessageVersion do
  @moduledoc """
  Ecto schema for archived versions of dialog messages.

  Spec: `docs/reqs/pq_dialogs.md` §2a `dialog_messages_versions`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.Types.UserHash

  @primary_key false

  schema "dialog_messages_versions" do
    field(:message_id, DialogMessageId, primary_key: true)
    field(:sign_hash, DialogMessageSignHash, primary_key: true)
    field(:dialog_hash, DialogHash)
    field(:sender_hash, UserHash)
    field(:content_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:refs_map_b64, :binary)
    field(:parent_sign_hash, DialogMessageSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :message_id,
      :sign_hash,
      :dialog_hash,
      :sender_hash,
      :content_b64,
      :deleted_flag,
      :refs_map_b64,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64
    ])
    |> validate_required([
      :message_id,
      :sign_hash,
      :dialog_hash,
      :sender_hash,
      :deleted_flag,
      :owner_timestamp,
      :sign_b64
    ])
    |> unique_constraint([:message_id, :sign_hash],
      name: :dialog_messages_versions_pkey
    )
  end
end
