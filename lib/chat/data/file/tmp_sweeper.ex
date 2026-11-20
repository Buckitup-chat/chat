defmodule Chat.Data.File.TmpSweeper do
  @moduledoc "Per-drive periodic cleanup of stale .tmp chunk files."

  @behaviour :gen_statem

  alias Chat.Data.File.ChunkStore
  alias Chat.Storage.Unit

  @registry Chat.Data.File.ChunkPipelineRegistry
  @interval :timer.hours(1)

  def start_link(opts) do
    %Unit{id: drive_id} = Keyword.fetch!(opts, :unit)
    :gen_statem.start_link(via(drive_id), __MODULE__, opts, [])
  end

  def child_spec(opts) do
    %Unit{id: drive_id} = Keyword.fetch!(opts, :unit)

    %{
      id: {__MODULE__, drive_id},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(opts) do
    data = %{unit: Keyword.fetch!(opts, :unit)}
    {:ok, :sweeping, data, [{:next_event, :internal, :sweep}]}
  end

  def sweeping(:internal, :sweep, data) do
    ChunkStore.sweep_tmp_files(data.unit, @interval)
    {:next_state, :cooldown, data, [{:state_timeout, @interval, :sweep}]}
  end

  def cooldown(:state_timeout, :sweep, data) do
    {:next_state, :sweeping, data, [{:next_event, :internal, :sweep}]}
  end

  def cooldown(:cast, :force_sweep, data) do
    {:next_state, :sweeping, data, [{:next_event, :internal, :sweep}]}
  end

  defp via(drive_id), do: {:via, Registry, {@registry, {:tmp_sweeper, drive_id}}}
end
