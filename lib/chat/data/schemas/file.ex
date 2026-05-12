defmodule Chat.Data.Schemas.File do
  @moduledoc "Ecto schema for file manifests. One row per completed file upload."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.FileId
  alias Chat.Data.Types.UserHash

  @primary_key {:file_id, FileId, []}

  @create_fields [
    :file_id,
    :uploader_hash,
    :total_size,
    :chunk_size,
    :chunk_count,
    :chunk_sign_hashes,
    :owner_timestamp,
    :deleted_flag,
    :sign_b64
  ]
  @create_required @create_fields
  @delete_fields [:deleted_flag, :chunk_sign_hashes, :owner_timestamp, :sign_b64]

  schema "files" do
    field(:uploader_hash, UserHash)
    field(:total_size, :integer)
    field(:chunk_size, :integer, default: 4_194_304)
    field(:chunk_count, :integer)
    field(:chunk_sign_hashes, {:array, :binary})
    field(:owner_timestamp, :integer)
    field(:deleted_flag, :boolean, default: false)
    field(:sign_b64, :binary)
  end

  def create_changeset(file, attrs) do
    file
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:file_id, name: :files_pkey)
  end

  def delete_changeset(file, attrs) do
    file
    |> cast(attrs, @delete_fields)
    |> validate_required(@delete_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(file) do
      file
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(file), do: User.get_card(file.uploader_hash).sign_pkey

    def signature(file), do: file.sign_b64
  end
end
