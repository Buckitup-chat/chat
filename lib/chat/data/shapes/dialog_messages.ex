defmodule Chat.Data.Shapes.DialogMessages do
  @moduledoc "Shape behaviour implementation for dialog_messages"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageVersion
  alias Chat.Data.Types.DialogMessageSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :dialog_messages

  @impl true
  def schema_module, do: DialogMessage

  @impl true
  def versions_schema, do: DialogMessageVersion

  @impl true
  def sync_required_parents(_op, %{sender_hash: hash, dialog_hash: dh}) do
    [{:user_card, hash}, {:dialog_keys, {dh, hash}}]
  end

  @impl true
  def sync_derive_fields(%DialogMessage{sign_b64: sign_b64} = message) do
    case sign_b64 do
      bin when is_binary(bin) ->
        sign_hash =
          bin
          |> EnigmaPq.hash()
          |> DialogMessageSignHash.from_binary()

        %{message | sign_hash: sign_hash}

      _ ->
        message
    end
  end

  @impl true
  def sync_persist(operation, message) do
    case operation do
      :insert ->
        message
        |> Validation.validate_message_insert()
        |> persist_insert(message)

      :update ->
        persist_update(message)
    end
  end

  defp persist_insert(changeset, message) do
    case changeset do
      %{valid?: true} ->
        upsert_message(changeset, message)

      %{valid?: false} = cs ->
        log("Invalid dialog_message insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, message}
    end
  end

  defp upsert_message(changeset, message) do
    case Dialog.get_message(message.message_id) do
      nil -> Dialog.insert_message(changeset)
      existing -> Dialog.insert_message_with_conflict(existing, message)
    end
  end

  defp persist_update(message) do
    with existing when not is_nil(existing) <- Dialog.get_message(message.message_id),
         %{valid?: true} <- Validation.validate_message_update(existing, message) do
      Dialog.update_message_with_versioning(existing, message)
    else
      nil ->
        {:ok, message}

      %{valid?: false} = cs ->
        log("Invalid dialog_message update signature: #{inspect(cs.errors)}", :warning)
        {:ok, message}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, DialogMessage,
      accept: [:insert, :update],
      check: &Validation.message_allowed(&1, user_pop_context),
      validate: &Validation.message_validate_with_versioning/3,
      insert: [
        pre_apply: &Validation.message_pre_apply_versioning/3
      ],
      update: [
        pre_apply: &Validation.message_pre_apply_versioning/3
      ]
    )
  end
end
