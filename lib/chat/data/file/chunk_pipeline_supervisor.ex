defmodule Chat.Data.File.ChunkPipelineSupervisor do
  @moduledoc """
  Supervisor for one storage unit's chunk admission pipeline.

  Takes `unit:` only; the drive id, repo and paths are derived from it. The
  unit's PG system id is read once here, so children get a complete unit.
  """

  use Supervisor

  alias Chat.Data.File.ChunkWriter
  alias Chat.Data.File.DriveCopySource
  alias Chat.Data.File.MissingChunksBackfill
  alias Chat.Data.File.ReplicationListener
  alias Chat.Data.File.SyncSource
  alias Chat.Data.File.TmpSweeper
  alias Chat.Storage.Pg
  alias Chat.Storage.Unit
  alias Chat.Storage.UnitAnnouncer

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    %Unit{} = unit = opts |> Keyword.fetch!(:unit) |> with_system_id()

    [
      ChunkWriter,
      MissingChunksBackfill,
      ReplicationListener,
      DriveCopySource,
      SyncSource,
      TmpSweeper,
      UnitAnnouncer
    ]
    |> Enum.map(&{&1, unit: unit})
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp with_system_id(%Unit{system_id: nil} = unit),
    do: %{unit | system_id: unit |> Unit.repo() |> Pg.system_identifier()}

  defp with_system_id(unit), do: unit
end
