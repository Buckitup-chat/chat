defmodule Chat.Data.File.ChunkPipelineSupervisor do
  @moduledoc "Supervisor for per-drive chunk admission pipeline."

  use Supervisor

  alias Chat.Data.File.ChunkWriter
  alias Chat.Data.File.DriveCopySource
  alias Chat.Data.File.MissingChunksBackfill
  alias Chat.Data.File.ReplicationListener
  alias Chat.Data.File.SyncSource
  alias Chat.Data.File.TmpSweeper
  alias Chat.Storage.Unit
  alias Chat.Storage.UnitAnnouncer

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    base_dir = Keyword.get(opts, :base_dir)
    repo = Keyword.get(opts, :repo)
    unit = Keyword.get_lazy(opts, :unit, fn -> legacy_unit(drive_id) end)

    children = [
      {ChunkWriter, drive_id: drive_id, base_dir: base_dir},
      {MissingChunksBackfill, base_dir: base_dir, repo: repo},
      {ReplicationListener, drive_id: drive_id, repo: repo},
      {DriveCopySource, drive_id: drive_id, repo: repo},
      {SyncSource, drive_id: drive_id, repo: repo},
      {TmpSweeper, drive_id: drive_id, base_dir: base_dir},
      {UnitAnnouncer, unit: unit, repo: repo}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Until #802 callers pass `unit:`: only the internal unit is known by its drive id
  defp legacy_unit(:internal), do: Unit.internal()
  defp legacy_unit(_device), do: nil
end
