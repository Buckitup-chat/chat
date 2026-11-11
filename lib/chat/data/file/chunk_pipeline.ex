defmodule Chat.Data.File.ChunkPipeline do
  @moduledoc "Convenience functions for the chunk write pipeline."

  alias Chat.Db.Common
  alias Chat.Storage.Unit
  alias Chat.Storage.Units

  def active_drive_id do
    Common.get_chat_db_env(:active_drive_id)
  end

  def set_active_drive_id(drive_id) do
    Common.put_chat_db_env(:active_drive_id, drive_id)
  end

  @doc """
  The unit chunks are read from and uploaded to at the edges (controllers, GC).

  Temporary until #804 (`Chat.Storage.Default`): derived from the active drive
  id. A USB drive becomes active only as main, so an unregistered one falls back
  to its main unit.
  """
  @spec active_unit() :: Unit.t()
  def active_unit do
    case active_drive_id() do
      nil -> Unit.internal()
      :internal -> Unit.internal()
      device -> Units.by_id(device) |> or_main(device)
    end
  end

  defp or_main({:ok, unit}, _device), do: unit
  defp or_main(:error, device), do: Unit.usb(device, :main)
end
