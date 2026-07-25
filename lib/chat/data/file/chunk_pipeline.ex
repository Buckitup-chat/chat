defmodule Chat.Data.File.ChunkPipeline do
  @moduledoc "Convenience functions for the chunk write pipeline."

  alias Chat.Db.Common

  def active_drive_id do
    Common.get_chat_db_env(:active_drive_id)
  end

  def set_active_drive_id(drive_id) do
    Common.put_chat_db_env(:active_drive_id, drive_id)
  end
end
