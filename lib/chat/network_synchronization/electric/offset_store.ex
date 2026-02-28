defmodule Chat.NetworkSynchronization.Electric.OffsetStore do
  @moduledoc """
  Persists Electric shape resume offsets to CubDB (AdminDb).

  Uses PostgreSQL system_identifier instead of peer_url for reliable
  peer identification across DHCP network changes.
  """

  alias Chat.NetworkSynchronization.Electric.Shapes

  @electric_sync_offset :electric_sync_offset

  def save(system_identifier, shape, resume) do
    Chat.AdminDb.put({@electric_sync_offset, system_identifier, shape}, resume)
  end

  def load(system_identifier, shape) do
    Chat.AdminDb.get({@electric_sync_offset, system_identifier, shape})
  end

  def delete(system_identifier) do
    db = Chat.AdminDb.db()
    Shapes.all() |> Enum.each(&CubDB.delete(db, {@electric_sync_offset, system_identifier, &1}))
  end
end
