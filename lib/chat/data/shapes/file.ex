defmodule Chat.Data.Shapes.File do
  @moduledoc "Shape behaviour implementation for files (manifests)"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.Validation
  alias Chat.Data.Schemas.File
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :file

  @impl true
  def schema_module, do: File

  @impl true
  def sync_required_parents(_op, %{uploader_hash: hash}), do: [{:user_card, hash}]

  @impl true
  def sync_persist(operation, file) do
    case operation do
      :insert ->
        file
        |> Validation.validate_file_insert()
        |> persist_insert(file)

      :update ->
        persist_update(file)
    end
  end

  defp persist_insert(changeset, file) do
    case changeset do
      %{valid?: true} ->
        FileData.upsert_file(changeset)

      %{valid?: false} = cs ->
        log("Invalid file insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, file}
    end
  end

  defp persist_update(file) do
    with existing when not is_nil(existing) <- FileData.get_file(file.file_id),
         %{valid?: true} <- Validation.validate_file_update(existing, file) do
      FileData.update_file(existing, file)
    else
      nil ->
        {:ok, file}

      %{valid?: false} = cs ->
        log("Invalid file update signature: #{inspect(cs.errors)}", :warning)
        {:ok, file}
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, File,
      accept: [:insert, :update],
      check: &Validation.file_allowed(&1, user_pop_context),
      validate: &Validation.file_validate/3,
      insert: [pre_apply: &Validation.file_pre_apply_insert/3],
      update: [pre_apply: &Validation.file_pre_apply_update/3]
    )
  end
end
