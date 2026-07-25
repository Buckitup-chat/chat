defmodule Chat.Data.File.TmpSweeper do
  @moduledoc "Per-drive periodic cleanup of stale .tmp chunk files."

  @behaviour :gen_statem

  alias Chat.Data.File.ChunkStore

  @registry Chat.Data.File.ChunkPipelineRegistry
  @interval :timer.hours(1)

  def start_link(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)
    :gen_statem.start_link(via(drive_id), __MODULE__, opts, [])
  end

  def child_spec(opts) do
    drive_id = Keyword.fetch!(opts, :drive_id)

    %{
      id: {__MODULE__, drive_id},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(opts) do
    data = %{base_dir: Keyword.get(opts, :base_dir)}
    {:ok, :sweeping, data, [{:next_event, :internal, :sweep}]}
  end

  def sweeping(:internal, :sweep, data) do
    ChunkStore.sweep_tmp_files(@interval, data.base_dir)
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
