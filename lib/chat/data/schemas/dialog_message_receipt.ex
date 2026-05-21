defmodule Chat.Data.Schemas.DialogMessageReceipt do
  @moduledoc "Ecto schema for plaintext delivery and read receipts on dialog messages."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReceiptHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.Types.UserHash

  @primary_key {:receipt_hash, DialogMessageReceiptHash, []}

  @create_fields [
    :receipt_hash,
    :dialog_hash,
    :message_id,
    :peer_hash,
    :type,
    :message_sign_hash,
    :owner_timestamp,
    :sign_b64
  ]
  @create_required @create_fields

  schema "dialog_message_receipts" do
    field(:dialog_hash, DialogHash)
    field(:message_id, DialogMessageId)
    field(:peer_hash, UserHash)
    field(:type, :string)
    field(:message_sign_hash, DialogMessageSignHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(receipt, attrs) do
    receipt
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> validate_inclusion(:type, ["delivered", "read"])
    |> unique_constraint(:receipt_hash, name: :dialog_message_receipts_pkey)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(receipt) do
      receipt
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(receipt), do: User.get_card(receipt.peer_hash).sign_pkey

    def signature(receipt), do: receipt.sign_b64
  end
end
