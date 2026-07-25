defmodule Chat.Data.Schemas.MissingChunk do
  @moduledoc "Tracks chunks not yet fetched by the receiving device. Local only, not Electric-synced."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.FileChunkDataHash
  alias Chat.Data.Types.FileId

  @primary_key false

  @create_fields [:file_id, :chunk_index, :peer_url, :source_drive_id, :updated_at]
  @create_required [:file_id, :chunk_index, :updated_at]
  @fill_fields [:data_hash, :size]

  schema "missing_chunks" do
    field(:file_id, FileId, primary_key: true)
    field(:chunk_index, :integer, primary_key: true)
    field(:data_hash, FileChunkDataHash)
    field(:size, :integer)
    field(:peer_url, :string)
    field(:source_drive_id, :string)
    field(:attempts, :integer, default: 0)
    field(:updated_at, :integer)
  end

  def create_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:file_id, :chunk_index], name: :missing_chunks_pkey)
  end

  def fill_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, @fill_fields)
    |> validate_required(@fill_fields)
  end
end
