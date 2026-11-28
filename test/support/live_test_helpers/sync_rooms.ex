defmodule ChatWeb.LiveTestHelpers.SyncRooms do
  @moduledoc """
  Resets the cargo and USB drive dump room state between LiveView tests.
  """

  alias Chat.{AdminDb, Db}
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}

  @doc "Clears both CubDB databases and removes any cargo or dump room flow."
  def reset_sync_rooms do
    AdminDb.db() |> CubDB.clear()
    Db.db() |> CubDB.clear()
    CargoRoom.remove()
    UsbDriveDumpRoom.remove()
  end
end
