defmodule Chat.Data.Shapes.DialogKeys do
  @moduledoc "Shape behaviour implementation for dialog_keys"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Schemas.DialogKey
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :dialog_keys

  @impl true
  def schema_module, do: DialogKey

  @impl true
  def sync_required_parents(_op, %{sender_hash: hash}), do: [{:user_card, hash}]

  @impl true
  def sync_persist(operation, dialog_key) do
    case operation do
      :insert ->
        dialog_key
        |> Validation.validate_dialog_key_insert()
        |> persist_insert(dialog_key)

      :update ->
        persist_update(dialog_key)
    end
  end

  defp persist_insert(changeset, dialog_key) do
    case changeset do
      %{valid?: true} ->
        Dialog.upsert_dialog_key(changeset)

      %{valid?: false} = cs ->
        log("Invalid dialog_key insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, dialog_key}
    end
  end

  defp persist_update(dialog_key) do
    case Dialog.get_dialog_key(dialog_key.dialog_hash, dialog_key.sender_hash) do
      nil ->
        {:ok, dialog_key}

      existing ->
        existing
        |> Validation.validate_dialog_key_update(dialog_key)
        |> apply_changeset(dialog_key)
    end
  end

  defp apply_changeset(changeset, dialog_key) do
    case changeset do
      %{valid?: true} ->
        Dialog.upsert_dialog_key(
          DialogKey.create_changeset(%DialogKey{}, Map.from_struct(dialog_key))
        )

      %{valid?: false, action: :ignore} ->
        {:ok, dialog_key}

      %{valid?: false} = cs ->
        log("Invalid dialog_key update signature: #{inspect(cs.errors)}", :warning)
        {:ok, dialog_key}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, DialogKey,
      accept: [:insert, :update],
      check: &Validation.dialog_key_allowed(&1, user_pop_context),
      validate: &Validation.dialog_key_validate/3
    )
  end
end
