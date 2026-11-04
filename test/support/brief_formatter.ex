defmodule Chat.Test.BriefFormatter do
  @moduledoc """
  ExUnit formatter that records only failures, one short line each.

  Writes to the file in `BRIEF_FAILURES_FILE` (default `_build/test_failures.txt`)
  so the summary stays clean even when the suite's stdout is noisy.
  Used by `make test-brief`.
  """
  use GenServer

  @max_reason 300

  @impl true
  def init(opts) do
    {:ok, %{seed: opts[:seed], failures: [], total: 0, excluded: 0, skipped: 0}}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: nil}}, state),
    do: {:noreply, %{state | total: state.total + 1}}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _}}}, state),
    do: {:noreply, %{state | excluded: state.excluded + 1}}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:skipped, _}}}, state),
    do: {:noreply, %{state | skipped: state.skipped + 1}}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:invalid, _}} = test}, state),
    do: {:noreply, add_failure(state, test, "invalid: setup_all failed")}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, failures}} = test}, state),
    do: {:noreply, add_failure(state, test, short_reason(failures))}

  def handle_cast({:module_finished, %ExUnit.TestModule{state: {:failed, failures}} = mod}, state) do
    line = "#{mod.file}  #{inspect(mod.name)} setup_all  -- #{short_reason(failures)}"
    {:noreply, %{state | failures: [line | state.failures]}}
  end

  def handle_cast({:suite_finished, times}, state) do
    write_summary(state, times)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp add_failure(state, test, reason) do
    location = "#{Path.relative_to_cwd(test.tags.file)}:#{test.tags.line}"
    line = "#{location}  #{test.name}  -- #{reason}"
    %{state | total: state.total + 1, failures: [line | state.failures]}
  end

  defp short_reason([{kind, reason, _stack} | _]) do
    kind
    |> Exception.format_banner(reason, [])
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, @max_reason)
  end

  defp write_summary(state, times) do
    seconds = Float.round(Map.get(times, :run, 0) / 1_000_000, 1)
    failed = length(state.failures)

    header =
      "#{state.total} tests, #{failed} failures, #{state.excluded} excluded, " <>
        "#{state.skipped} skipped, #{seconds}s, seed #{state.seed}"

    [header | Enum.reverse(state.failures)]
    |> Enum.join("\n")
    |> then(&File.write!(summary_file(), &1 <> "\n"))
  end

  defp summary_file, do: System.get_env("BRIEF_FAILURES_FILE", "_build/test_failures.txt")
end
