defmodule Chat.Data.Shapes.DialogMessageReactions do
  @moduledoc "Shape behaviour implementation for dialog_message_reactions"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Dialog
  alias Chat.Data.Dialog.Validation
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :dialog_message_reactions

  @impl true
  def schema_module, do: DialogMessageReaction

  @impl true
  def sync_required_parents(_op, %{reactor_hash: hash}), do: [{:user_card, hash}]

  @impl true
  def sync_persist(operation, reaction) do
    case operation do
      :insert ->
        reaction
        |> Validation.validate_reaction_insert()
        |> persist_insert(reaction)

      :update ->
        persist_update(reaction)
    end
  end

  defp persist_insert(changeset, reaction) do
    case changeset do
      %{valid?: true} ->
        Dialog.upsert_reaction(changeset)

      %{valid?: false} = cs ->
        log("Invalid dialog_message_reaction insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, reaction}
    end
  end

  defp persist_update(reaction) do
    case Dialog.get_reaction(reaction.reaction_hash) do
      nil ->
        {:ok, reaction}

      existing ->
        existing
        |> Validation.validate_reaction_update(reaction)
        |> apply_changeset(reaction)
    end
  end

  defp apply_changeset(changeset, reaction) do
    case changeset do
      %{valid?: true} ->
        Dialog.upsert_reaction(
          DialogMessageReaction.create_changeset(
            %DialogMessageReaction{},
            Map.from_struct(reaction)
          )
        )

      %{valid?: false, action: :ignore} ->
        {:ok, reaction}

      %{valid?: false} = cs ->
        log("Invalid dialog_message_reaction update signature: #{inspect(cs.errors)}", :warning)
        {:ok, reaction}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, DialogMessageReaction,
      accept: [:insert, :update],
      check: &Validation.reaction_allowed(&1, user_pop_context),
      validate: &Validation.reaction_validate/3
    )
  end
end
