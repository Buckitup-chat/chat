defmodule Chat.Db.Boot.ElectricReady do
  @moduledoc "Stage: verify Electric/Phoenix.Sync stack is alive."

  use GracefulGenServer
  use Toolbox.OriginLog

  alias Toolbox.StagedSupervisor

  @impl true
  def on_init(opts) do
    next = Keyword.get(opts, :next)

    %{next: next}
    |> tap(fn _ -> send(self(), :start) end)
  end

  @impl GracefulGenServer
  def on_msg(:start, state) do
    verify_electric()
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

  defp verify_electric do
    case Process.whereis(Phoenix.Sync.Supervisor) do
      pid when is_pid(pid) ->
        log("Phoenix.Sync.Supervisor is alive", :info)

      nil ->
        log("Phoenix.Sync.Supervisor not found, Electric may initialize later", :warning)
    end
  end
end
