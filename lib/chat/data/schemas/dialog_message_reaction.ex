defmodule Chat.Data.Schemas.DialogMessageReaction do
  @moduledoc """
  Ecto schema for encrypted emoji reactions on dialog messages.

  Spec: `docs/reqs/pq_dialogs.md` §3 `dialog_message_reactions`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReactionHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.Types.UserHash

  @primary_key {:reaction_hash, DialogMessageReactionHash, []}

  @create_fields [
    :reaction_hash,
    :dialog_hash,
    :message_id,
    :message_sign_hash,
    :reactor_hash,
    :type_b64,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64
  ]
  @create_required @create_fields
  @update_fields [:type_b64, :deleted_flag, :owner_timestamp, :sign_b64]

  schema "dialog_message_reactions" do
    field(:dialog_hash, DialogHash)
    field(:message_id, DialogMessageId)
    field(:message_sign_hash, DialogMessageSignHash)
    field(:reactor_hash, UserHash)
    field(:type_b64, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(reaction, attrs) do
    reaction
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:reaction_hash, name: :dialog_message_reactions_pkey)
  end

  def update_changeset(reaction, attrs) do
    reaction
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(reaction) do
      reaction
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(reaction), do: User.get_card(reaction.reactor_hash).sign_pkey

    def signature(reaction), do: reaction.sign_b64
  end
end
