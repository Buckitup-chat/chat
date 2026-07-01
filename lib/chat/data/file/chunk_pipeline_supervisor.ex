defmodule Chat.Data.File.ChunkPipelineSupervisor do
  @moduledoc "Supervisor for per-drive chunk admission pipeline."

  use Supervisor

  alias Chat.Data.File.ChunkWriter
  alias Chat.Data.File.DriveCopySource
  alias Chat.Data.File.ReplicationListener
  alias Chat.Data.File.SyncSource
  alias Chat.Data.File.TmpSweeper

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    base_dir = Keyword.get(opts, :base_dir)
    repo = Keyword.get(opts, :repo)

    children = [
      {ChunkWriter, drive_id: drive_id, base_dir: base_dir},
      {ReplicationListener, drive_id: drive_id, repo: repo},

      {DriveCopySource, drive_id: drive_id, repo: repo},
      {SyncSource, drive_id: drive_id, repo: repo},
      {TmpSweeper, drive_id: drive_id, base_dir: base_dir}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
