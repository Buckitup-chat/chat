defmodule Chat.Data.Shapes.DialogMessageReceipts do
  @moduledoc "Shape behaviour implementation for dialog_message_receipts"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :dialog_message_receipts

  @impl true
  def schema_module, do: DialogMessageReceipt

  @impl true
  def sync_required_parents(_op, %{peer_hash: hash}), do: [{:user_card, hash}]

  @impl true
  def sync_persist(:insert, receipt) do
    receipt
    |> Validation.validate_receipt_insert()
    |> persist_insert(receipt)
  end

  defp persist_insert(changeset, receipt) do
    case changeset do
      %{valid?: true} ->
        Dialog.upsert_receipt(changeset)

      %{valid?: false} = cs ->
        log("Invalid dialog_message_receipt insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, receipt}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, DialogMessageReceipt,
      accept: [:insert],
      check: &Validation.receipt_allowed(&1, user_pop_context),
      validate: &Validation.receipt_validate/3
    )
  end
end
