defmodule Chat.Data.Schemas.FileChunk do
  @moduledoc "Ecto schema for file chunks. Contains encrypted blob data (~4 MB each)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.FileId
  alias Chat.Data.Types.UserHash

  @primary_key false

  @create_fields [
    :file_id,
    :chunk_index,
    :data_b64,
    :size,
    :uploader_hash,
    :owner_timestamp,
    :sign_b64
  ]
  @create_required @create_fields

  schema "file_chunks" do
    field(:file_id, FileId, primary_key: true)
    field(:chunk_index, :integer, primary_key: true)
    field(:data_b64, :binary)
    field(:size, :integer)
    field(:uploader_hash, UserHash)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint([:file_id, :chunk_index], name: :file_chunks_pkey)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    alias Chat.Data.User

    def signable_fields(chunk) do
      chunk
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(chunk), do: User.get_card(chunk.uploader_hash).sign_pkey

    def signature(chunk), do: chunk.sign_b64
  end
end
