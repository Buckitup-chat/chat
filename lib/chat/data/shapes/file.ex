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
