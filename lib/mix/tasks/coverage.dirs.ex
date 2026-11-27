defmodule Mix.Tasks.Coverage.Dirs do
  @shortdoc "Fails when a directory's line coverage drops below its threshold"
  @moduledoc """
  Checks per-directory line coverage from the `mix coveralls.json` report.

  ExCoveralls only enforces a global `minimum_coverage`. This task aggregates the
  per-file line arrays of `cover/excoveralls.json` by path prefix and fails when a
  prefix is below its minimum. Thresholds live in `coveralls.json` under
  `"dir_thresholds"` (path prefix => minimum percent), next to `skip_files`.

      MIX_ENV=test mix coveralls.json && MIX_ENV=test mix coverage.dirs

  Options: `--report` (default `cover/excoveralls.json`), `--config` (default `coveralls.json`).
  """
  use Mix.Task

  @config "coveralls.json"
  @report "cover/excoveralls.json"

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [report: :string, config: :string])

    thresholds =
      opts
      |> Keyword.get(:config, @config)
      |> read_json()
      |> Map.fetch!("dir_thresholds")

    opts
    |> Keyword.get(:report, @report)
    |> read_json()
    |> Map.fetch!("source_files")
    |> check(thresholds)
    |> tap(&Enum.each(&1, fn result -> result |> format() |> Mix.shell().info() end))
    |> Enum.reject(& &1.ok?)
    |> case do
      [] -> :ok
      failed -> Mix.raise("Coverage below threshold: #{failed |> Enum.map_join(", ", & &1.dir)}")
    end
  end

  @doc "Coverage percent per threshold prefix. A prefix matching no relevant lines counts as 0%."
  def check(source_files, thresholds) do
    thresholds
    |> Enum.sort()
    |> Enum.map(fn {dir, min} ->
      percent =
        source_files
        |> Enum.filter(&String.starts_with?(&1["name"], dir))
        |> Enum.flat_map(& &1["coverage"])
        |> line_percent()

      %{dir: dir, percent: percent, min: min, ok?: percent >= min}
    end)
  end

  defp line_percent(lines) do
    relevant = lines |> Enum.reject(&is_nil/1)
    covered = relevant |> Enum.count(&(&1 > 0))

    case relevant do
      [] -> 0.0
      _ -> covered * 100 / length(relevant)
    end
  end

  defp format(%{dir: dir, percent: percent, min: min, ok?: ok?}),
    do: "#{if ok?, do: "ok  ", else: "FAIL"} #{dir} #{Float.round(percent, 1)}% (min #{min}%)"

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()
end
