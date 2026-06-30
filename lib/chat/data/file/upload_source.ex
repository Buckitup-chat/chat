defmodule Chat.Data.File.UploadSource do
  @moduledoc "Sink for client-uploaded chunks. Routes to the drive's ChunkWriter."

  alias Chat.Data.File.ChunkWriter

  def submit(drive_id, chunk_data, meta) do
    ChunkWriter.submit(drive_id, :upload, chunk_data, meta)
  end
end
