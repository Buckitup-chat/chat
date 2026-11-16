defmodule Chat.Storage.PlanRunner do
  @moduledoc """
  Runs a scenario's plan: a list of steps, executed in order.

      [
        {:bootstrap, internal ~> main},
        {:replicate, internal ~> main},
        {:bootstrap, main ~> internal},
        {:stop, internal ~> main},
        {:replicate, main ~> internal},
        {:switch_default, main}
      ]

  Steps:
  - `{:bootstrap, link}`, `{:replicate, link}` — run in the link's `LinkRunner`,
    started on first use and linked to this process
  - `{:stop, link}` — stops that runner, which tears the link down
  - `{:await, links, :chunks}` — `Link.await/3`
  - `{:switch_default, unit}` — the `:switch_default` callback (`Default.switch_to/1`)
  - `:eject` — the `:eject` callback

  A step returning `{:error, _}` (or crashing) halts the plan; `{:partial, _}` and a
  stalled await are recorded and the plan goes on. Steps other than `:stop` run in a
  task under `Chat.TaskSupervisor`, so `info/1` answers while a step takes as long as
  it needs. When the runner exits, the running step is killed and every link it
  still runs is stopped.

  Options: `plan:` (required), `switch_default:` (fun/1), `eject:` (fun/0),
  `await:` (opts for `Link.await/3`), `link_runner:` (opts for `LinkRunner`).

  See `docs/pq/reqs/files/pq_storage_units.done.md` §2.7.3–2.7.4.
  """

  use GracefulGenServer
  use Toolbox.OriginLog

  alias Chat.Storage.Link
  alias Chat.Storage.LinkRunner

  @type step ::
          {:bootstrap | :replicate | :stop, Link.t()}
          | {:await, [Link.t()], :chunks}
          | {:switch_default, Chat.Storage.Unit.t()}
          | :eject
  @type status :: :running | :done | {:halted, step(), term()}

  @doc "`%{status: status, results: [{step, result}]}`, oldest first."
  @spec info(GenServer.server()) :: %{status: status(), results: [{step(), term()}]}
  def info(runner), do: GenServer.call(runner, :info)

  @impl GracefulGenServer
  def on_init(opts) do
    send(self(), :next)

    %{
      steps: Keyword.fetch!(opts, :plan),
      opts: opts,
      runners: %{},
      results: [],
      status: :running,
      task: nil
    }
  end

  @impl GenServer
  def handle_call(:info, _from, state),
    do: {:reply, %{status: state.status, results: Enum.reverse(state.results)}, state}

  @impl GracefulGenServer
  def on_msg(:next, %{steps: []} = state) do
    log("plan done", :info)
    {:noreply, %{state | status: :done}}
  end

  def on_msg(:next, %{steps: [step | _]} = state) do
    case run(step, state) do
      {:done, result, state} -> finish(state, result)
      {:async, job, state} -> {:noreply, %{state | task: start_task(job)}}
    end
  end

  def on_msg({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    finish(%{state | task: nil}, result)
  end

  def on_msg({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state),
    do: finish(%{state | task: nil}, {:error, {:step_crashed, reason}})

  # Steps run in a task, so replies meant for them can land there; anything
  # else that reaches this process is ignored
  def on_msg(_msg, state), do: {:noreply, state}

  @impl GracefulGenServer
  def on_exit(_reason, %{runners: runners, task: task}) do
    kill_step(task)
    runners |> Map.values() |> Enum.each(&stop_runner/1)
  end

  defp kill_step(nil), do: :ok
  defp kill_step(%Task{} = task), do: Task.shutdown(task, :brutal_kill)

  defp finish(%{steps: [step | rest]} = state, result) do
    state = %{state | steps: rest, results: [{step, result} | state.results]}

    case result do
      {:error, reason} ->
        log("plan halted at #{inspect(step_name(step))}: #{inspect(reason)}", :error)
        {:noreply, %{state | status: {:halted, step, reason}}}

      _ ->
        send(self(), :next)
        {:noreply, state}
    end
  end

  # Link runners and their bookkeeping stay in this process; only the
  # (possibly long) work runs in a task, so `info/1` and stopping stay prompt
  defp run(step, state) do
    case step do
      {:bootstrap, link} ->
        with_runner(state, link, &LinkRunner.bootstrap/1)

      {:replicate, link} ->
        with_runner(state, link, &LinkRunner.replicate/1)

      {:stop, link} ->
        {:done, :ok, stop_link(state, link)}

      {:await, links, :chunks} ->
        {:async, fn -> Link.await(links, :chunks, state.opts[:await] || []) end, state}

      {:switch_default, unit} ->
        {:async, fn -> callback(state, :switch_default, [unit]) end, state}

      :eject ->
        {:async, fn -> callback(state, :eject, []) end, state}
    end
  end

  defp start_task(job), do: Task.Supervisor.async_nolink(Chat.TaskSupervisor, job)

  defp with_runner(state, link, operation) do
    id = Link.id(link)

    {runner, state} =
      case state.runners do
        %{^id => runner} ->
          {runner, state}

        runners ->
          runner_opts = Keyword.put(state.opts[:link_runner] || [], :link, link)
          {:ok, runner} = LinkRunner.start_link(runner_opts)
          {runner, %{state | runners: Map.put(runners, id, runner)}}
      end

    {:async, fn -> operation.(runner) end, state}
  end

  defp stop_link(state, link) do
    case Map.pop(state.runners, Link.id(link)) do
      {nil, _runners} ->
        Link.stop(link)
        state

      {runner, runners} ->
        stop_runner(runner)
        %{state | runners: runners}
    end
  end

  defp stop_runner(runner), do: if(Process.alive?(runner), do: GenServer.stop(runner))

  defp callback(state, name, args) do
    case state.opts[name] do
      fun when is_function(fun, length(args)) -> apply(fun, args)
      nil -> {:error, {:no_callback, name}}
    end
  end

  defp step_name({name, _link}), do: name
  defp step_name({name, _links, _what}), do: name
  defp step_name(name), do: name
end
