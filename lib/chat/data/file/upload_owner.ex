defmodule Chat.Data.File.UploadOwner do
  @moduledoc """
  Decides whether a signed chunk may be stored under its `file_id`.

  A `file_id` is client-chosen and visible to others only through the
  `file_chunks` shape, so the uploader of its first stored chunk owns it until
  the manifest lands, and the `files` row owns it after that. A stored chunk is
  never replaced: the same signed chunk again is a no-op, any other is refused.
  """

  alias Chat.Data.File, as: FileData
  alias Chat.Data.Schemas.FileChunk

  def check(%FileChunk{file_id: file_id, uploader_hash: uploader_hash} = chunk) do
    with :ok <- check_file(file_id, uploader_hash),
         :ok <- check_chunks(file_id, uploader_hash) do
      check_index(chunk)
    end
  end

  defp check_file(file_id, uploader_hash) do
    case FileData.get_file(file_id) do
      nil -> :ok
      %{deleted_flag: true} -> {:error, :file_deleted}
      %{uploader_hash: ^uploader_hash} -> :ok
      _ -> {:error, :uploader_mismatch}
    end
  end

  defp check_chunks(file_id, uploader_hash) do
    if FileData.chunks_of_other_uploader?(file_id, uploader_hash),
      do: {:error, :uploader_mismatch},
      else: :ok
  end

  defp check_index(%FileChunk{sign_b64: sign_b64} = chunk) do
    case FileData.get_file_chunk(chunk.file_id, chunk.chunk_index) do
      nil -> :ok
      %{sign_b64: ^sign_b64} -> :already_stored
      _ -> {:error, :chunk_exists}
    end
  end
end
