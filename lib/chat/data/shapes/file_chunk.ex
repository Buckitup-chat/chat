defmodule Chat.Data.Shapes.FileChunk do
  @moduledoc "Shape behaviour implementation for file_chunks"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.Validation
  alias Chat.Data.Schemas.FileChunk
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :file_chunk

  @impl true
  def schema_module, do: FileChunk

  @impl true
  def sync_required_parents(_op, %{file_id: file_id}), do: [{:file, file_id}]

  @impl true
  def sync_validate_parent({:file, _file_id}, chunk) do
    case FileData.get_file(chunk.file_id) do
      nil -> {:reject, :file_not_found}
      %{deleted_flag: true} -> {:reject, :file_deleted}
      %{uploader_hash: hash} when hash != chunk.uploader_hash -> {:reject, :uploader_mismatch}
      %{} -> :ok
    end
  end

  @impl true
  def sync_persist(:insert, chunk) do
    chunk
    |> Validation.validate_file_chunk_insert()
    |> persist_insert(chunk)
  end

  defp persist_insert(changeset, chunk) do
    case changeset do
      %{valid?: true} ->
        FileData.insert_file_chunk(changeset)

      %{valid?: false} = cs ->
        log("Invalid file_chunk insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, chunk}
    end
  end

  @impl true
  def sync_after_persist(operation, struct, opts) do
    case {operation, struct, Keyword.get(opts, :peer_url)} do
      {:insert, %FileChunk{} = chunk, peer_url} when is_binary(peer_url) ->
        fill_missing_chunk(chunk)

      _ ->
        :ok
    end
  end

  defp fill_missing_chunk(%FileChunk{} = chunk) do
    FileData.fill_missing_chunk(chunk.file_id, chunk.chunk_index, chunk.data_hash, chunk.size)
    :ok
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, FileChunk,
      accept: [:insert],
      check: &Validation.file_chunk_allowed(&1, user_pop_context),
      validate: &Validation.file_chunk_validate/3,
      insert: [pre_apply: &Validation.file_chunk_pre_apply_insert/3]
    )
  end
end
