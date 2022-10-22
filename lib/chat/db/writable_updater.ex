defmodule Chat.Db.WritableUpdater do
  @moduledoc "Checks and updated writable status of DB"

  use GenServer

  import Chat.Db.Common

  require Logger

  alias Chat.Db.Maintenance

  @debounce_buffer_ms :timer.seconds(1)
  @check_interval :timer.seconds(311)

  defstruct timer: nil, debounce_till: 0

  def check do
    __MODULE__
    |> GenServer.cast(:check)
  end

  def force_check do
    if get_chat_db_env(:mode) in [:main, :internal] do
      __MODULE__
      |> GenServer.call(:force_check, :timer.seconds(31))
    else
      check()
    end
  end

  #
  # GenServer implementation
  #

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, do_check(%__MODULE__{})}
  end

  @impl true
  def handle_call(:force_check, _, %__MODULE__{} = state) do
    state
    |> Map.put(:debounce_till, 0)
    |> do_check()
    |> reply(:ok)
  end

  @impl true
  def handle_cast(:check, %__MODULE__{} = state) do
    state
    |> do_check()
    |> noreply()
  end

  @impl true
  def handle_info(:check_writable, %__MODULE__{} = state) do
    state
    |> do_check()
    |> noreply()
  end

  #
  # Logic
  #

  defp do_check(%__MODULE__{debounce_till: till, timer: old_timer} = state) do
    if till < now_ms() do
      update_current_db_writable_size()
      if old_timer, do: Process.cancel_timer(old_timer)

      %__MODULE__{
        timer: schedule_writable_check(),
        debounce_till: now_ms() + @debounce_buffer_ms
      }
    else
      state
    end
  end

  defp schedule_writable_check do
    Process.send_after(self(), :check_writable, @check_interval)
  end

  defp update_current_db_writable_size do
    :data_pid
    |> get_chat_db_env()
    |> Maintenance.calc_write_budget()
    |> tap(fn size ->
      put_chat_db_env(:write_budget, size)
      put_chat_db_env(:writable, Maintenance.writable_by_write_budget(size))
      Logger.info("[db] free space checked. Budget = #{size}")
    end)
  rescue
    _ -> 0
  end

  defp now_ms, do: System.system_time(:millisecond)
  defp noreply(x), do: {:noreply, x}
  defp reply(x, result), do: {:reply, result, x}
end
