defmodule Chat.Db.Boot.ChunkPipelineReady do
  @moduledoc "Stage: start ChunkPipelineSupervisor for the internal drive."

  use GracefulGenServer
  use Toolbox.OriginLog

  alias Chat.Data.File.ChunkPipelineSupervisor
  alias Toolbox.StagedSupervisor

  @impl true
  def on_init(opts) do
    supervisor = Keyword.get(opts, :supervisor, Chat.RepoDynamicSupervisor)
    next = Keyword.get(opts, :next)

    %{supervisor: supervisor, next: next}
    |> tap(fn _ -> send(self(), :start) end)
  end

  @impl GracefulGenServer
  def on_msg(:start, %{supervisor: supervisor} = state) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        supervisor,
        {ChunkPipelineSupervisor, drive_id: :internal, repo: Chat.Repo}
      )

    log("ChunkPipelineSupervisor started for internal drive", :info)
    send(self(), :done)
    {:noreply, state}
  end

  def on_msg(:done, %{next: nil} = state), do: {:noreply, state}

  def on_msg(:done, %{next: next} = state) do
    StagedSupervisor.start_next_stage(next[:under], next[:run])
    {:noreply, state}
  end

  @impl true
  def on_exit(_reason, _state), do: :ok
end
