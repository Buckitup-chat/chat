defmodule Mix.Tasks.TooLong do
  @shortdoc "Fails when a source file is over the line limit and not in the baseline"
  @moduledoc """
  Enforces the 300-line file limit on `lib/` and `test/` (`*.ex`, `*.exs`, `*.heex`).

  Files that were already over the limit are listed in `.too_long_baseline` with their
  line count. The check fails when:

    * a file not in the baseline goes over the limit (`new`)
    * a baseline file grows past its recorded count (`grew`)
    * the baseline is stale — a file shrank, dropped under the limit or is gone (`stale`).
      Run `mix too_long --update` to record it, so the lower count becomes the new ceiling

  `--update` only lowers counts and removes entries; it never admits new or grown files.

      mix too_long
      mix too_long --update

  Options: `--baseline` (default `.too_long_baseline`), `--limit` (default 300).
  """
  use Mix.Task

  @baseline ".too_long_baseline"
  @limit 300
  @sources "{lib,test}/**/*.{ex,exs,heex}"

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args, strict: [baseline: :string, limit: :integer, update: :boolean])

    path = opts |> Keyword.get(:baseline, @baseline)
    limit = opts |> Keyword.get(:limit, @limit)
    baseline = path |> read_baseline()

    @sources
    |> Path.wildcard()
    |> Map.new(&{&1, line_count(&1)})
    |> check(baseline, limit)
    |> maybe_update(Keyword.get(opts, :update, false), baseline, path, limit)
    |> tap(&Enum.each(&1, fn result -> result |> format() |> Mix.shell().info() end))
    |> case do
      [] -> Mix.shell().info("No new or grown files over #{limit} lines")
      problems -> Mix.raise(failure_message(problems, limit))
    end
  end

  @doc """
  Problems found comparing current line counts with the baseline.

  Returns `%{path, status, lines, baseline}` maps, sorted by path, with status
  `:new`, `:grew` or `:stale`. An empty list means the check passes.
  """
  def check(counts, baseline, limit) do
    over =
      counts
      |> Enum.filter(fn {_, lines} -> lines > limit end)
      |> Enum.flat_map(fn {file, lines} ->
        case baseline |> Map.get(file) do
          nil -> [problem(file, :new, lines, nil)]
          base when lines > base -> [problem(file, :grew, lines, base)]
          _ -> []
        end
      end)

    stale =
      baseline
      |> Enum.flat_map(fn {file, base} ->
        lines = counts |> Map.get(file, 0)
        if lines < base, do: [problem(file, :stale, lines, base)], else: []
      end)

    (over ++ stale) |> Enum.sort_by(& &1.path)
  end

  @doc "Baseline with stale entries lowered to their current count, or dropped once under the limit."
  def shrink(baseline, problems, limit) do
    problems
    |> Enum.filter(&(&1.status == :stale))
    |> Enum.reduce(baseline, fn %{path: file, lines: lines}, acc ->
      if lines > limit, do: Map.put(acc, file, lines), else: Map.delete(acc, file)
    end)
  end

  defp maybe_update(problems, false, _baseline, _path, _limit), do: problems

  defp maybe_update(problems, true, baseline, path, limit) do
    baseline
    |> shrink(problems, limit)
    |> write_baseline(path)

    problems |> Enum.reject(&(&1.status == :stale))
  end

  defp problem(file, status, lines, base),
    do: %{path: file, status: status, lines: lines, baseline: base}

  defp format(%{path: file, status: :new, lines: lines}), do: "NEW   #{file} #{lines} lines"

  defp format(%{path: file, status: :grew, lines: lines, baseline: base}),
    do: "GREW  #{file} #{base} -> #{lines} lines"

  defp format(%{path: file, status: :stale, lines: lines, baseline: base}),
    do: "STALE #{file} #{base} -> #{lines} lines (run `mix too_long --update`)"

  defp failure_message(problems, limit) do
    hint =
      if Enum.any?(problems, &(&1.status != :stale)),
        do: " Split new or grown files to #{limit} lines or less.",
        else: ""

    "#{length(problems)} file(s) break the #{limit}-line limit baseline.#{hint}"
  end

  defp line_count(file), do: file |> File.read!() |> :binary.matches("\n") |> length()

  defp read_baseline(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Map.new(fn line ->
          [lines, file] = line |> String.split(" ", parts: 2)
          {file, String.to_integer(lines)}
        end)

      {:error, :enoent} ->
        %{}
    end
  end

  defp write_baseline(baseline, path) do
    baseline
    |> Enum.sort()
    |> Enum.map_join(fn {file, lines} -> "#{lines} #{file}\n" end)
    |> then(&File.write!(path, &1))
  end
end
