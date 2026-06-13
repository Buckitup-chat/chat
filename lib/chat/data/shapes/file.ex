defmodule Chat.Data.Shapes.File do
  @moduledoc "Shape behaviour implementation for files (manifests)"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.File, as: FileData
  alias Chat.Data.File.Validation
  alias Chat.Data.Schemas.File
  alias Chat.TimeKeeper
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :file

  @impl true
  def schema_module, do: File

  @impl true
  def sync_required_parents(_op, %{uploader_hash: hash}), do: [{:user_card, hash}]

  @doc """
  Decodes `chunk_sign_hashes` (`bytea[]`) elements back to raw binaries before
  signature validation in `sync_persist/2`.

  The Electric client's array decoder (`Electric.Client.EctoAdapter.ArrayDecoder`)
  only hex-decodes scalar bytea, not array elements: each element arrives as the
  double-escaped Postgres array-literal text (`\\x<hex>`) instead of the raw binary
  the uploader signed.
  """
  @impl true
  def sync_derive_fields(%File{chunk_sign_hashes: hashes} = file) do
    %{file | chunk_sign_hashes: Enum.map(hashes, &decode_bytea_element/1)}
  end

  defp decode_bytea_element("\\\\x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> binary
      :error -> "\\\\x" <> hex
    end
  end

  defp decode_bytea_element(binary), do: binary

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
    case FileData.get_file(file.file_id) do
      nil ->
        {:ok, file}

      existing ->
        existing
        |> Validation.validate_file_update(file)
        |> apply_update(existing, file)
    end
  end

  defp apply_update(changeset, existing, file) do
    case changeset do
      %{valid?: true} ->
        FileData.update_file(existing, file)

      %{valid?: false} = cs ->
        log("Invalid file update signature: #{inspect(cs.errors)}", :warning)
        {:ok, file}
    end
  end

  @impl true
  def sync_after_persist(operation, struct, opts) do
    case {operation, struct, Keyword.get(opts, :peer_url)} do
      {:insert, %File{} = file, peer_url} when is_binary(peer_url) ->
        preseed_missing_chunks(file, peer_url)

      _ ->
        :ok
    end
  end

  defp preseed_missing_chunks(%File{file_id: file_id, chunk_count: chunk_count}, peer_url) do
    FileData.insert_missing_chunks_placeholders(
      file_id,
      chunk_count,
      peer_url,
      TimeKeeper.now_unix()
    )

    :ok
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
