defmodule Chat.Data.Schemas.UploadChunk do
  @moduledoc "Ecto schema for upload bookkeeping. Local only, not Electric-synced."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.FileId
  alias Chat.Data.Types.UserHash

  @primary_key false

  @create_fields [:file_id, :chunk_index, :chunk_sign_hash, :uploader_hash, :size, :updated_at]
  @create_required @create_fields

  schema "upload_chunks" do
    field(:file_id, FileId, primary_key: true)
    field(:chunk_index, :integer, primary_key: true)
    field(:chunk_sign_hash, :binary)
    field(:uploader_hash, UserHash)
    field(:size, :integer)
    field(:updated_at, :integer)
  end

  def create_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:file_id, :chunk_index], name: :upload_chunks_pkey)
  end
end
