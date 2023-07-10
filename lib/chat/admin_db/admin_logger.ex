defmodule Chat.AdminDb.AdminLogger do
  @moduledoc """
  Logger into AdminDb

  It is logger backend and some helper functions to manage a few generations of logs.

  Each system start considered as a new generation.
  Every next message within generation has its own unique index.
  It is stored in CubDB with {:log, generation, index} key.
  """

  @behaviour :gen_event

  @impl :gen_event
  def init(_opts) do
    Process.send_after(:clear_old_generations, self(), :timer.minutes(5))
    generation = get_next_generation()
    Application.put_env(:chat, __MODULE__, generation)

    {:ok, %{current_generation: generation, next_index: 1}}
  end

  @impl :gen_event
  def handle_event(
        {level, _gl, {Logger, msg, ts, _md}},
        %{current_generation: generation, next_index: index} = state
      ) do
    {:log, generation, index}
    |> write_message({ts, level, msg})

    {:ok, %{state | next_index: index + 1}}
  end

  def handle_event(:flush, state) do
    sync_db()
    {:ok, state}
  end

  @impl :gen_event
  def handle_info(:clear_old_generations, %{current_genearion: gen} = state) do
    remove_old_generations(gen)
    {:ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl :gen_event
  def handle_call(_, state) do
    {:ok, {:ok, state}, state}
  end

  @impl :gen_event
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @impl :gen_event
  def terminate(_reason, _state) do
    :ok
  end

  def get_current_generation do
    Application.get_env(:chat, __MODULE__)
  end

  def get_log, do: get_log(get_current_generation())
  def get_log(:prev), do: get_log(get_current_generation() - 1)
  def get_log(:prev_prev), do: get_log(get_current_generation() - 2)

  def get_log(generation) do
    CubDB.select(Chat.AdminDb.db(),
      min_key: {:log, generation, 0},
      max_key: {:log, generation, nil}
    )
    |> Enum.to_list()
  end

  def get_next_generation do
    CubDB.select(Chat.AdminDb.db(), max_key: {:log, nil, nil}, reverse: true)
    |> Stream.take(1)
    |> Enum.to_list()
    |> case do
      [{{:log, generation, _}, _}] -> generation + 1
      _ -> 1
    end
  end

  defp write_message(key, value) do
    Chat.AdminDb.put(key, value)
  end

  defp remove_old_generations(generation) do
    Chat.AdminDb.db()
    |> CubDB.select(min_key: {:log, 0, 0}, max_key: {:log, generation - 3, nil})
    |> Stream.map(fn {k, _} -> k end)
    |> Enum.to_list()
    |> then(&CubDB.delete_multi(Chat.AdminDb.db(), &1))
  end

  defp sync_db do
    CubDB.file_sync(Chat.AdminDb.db())
  end
end
