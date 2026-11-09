defmodule Chat.Credo.Check.StrictModuleLayout do
  @moduledoc false

  use Credo.Check,
    id: "CHAT001",
    base_priority: :low,
    category: :readability,
    tags: [:controversial],
    param_defaults: [
      order: ~w/shortdoc moduledoc behaviour use import alias require/a,
      ignore: [],
      ignore_module_attributes: []
    ],
    explanations: [
      check: """
      Same as `Credo.Check.Readability.StrictModuleLayout`, with one exception:
      an `alias` may precede a `use` when the `use` arguments reference it.

          alias Chat.Data.Types.Consts

          use Chat.Data.Types.PrefixedHash, prefix: Consts.dialog_prefix()
      """,
      params: [
        order: "See `Credo.Check.Readability.StrictModuleLayout`.",
        ignore: "See `Credo.Check.Readability.StrictModuleLayout`.",
        ignore_module_attributes: "See `Credo.Check.Readability.StrictModuleLayout`."
      ]
    ]

  alias Credo.Check.Readability.StrictModuleLayout

  @use_after_alias "use must appear before alias"

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    exempt_lines = source_file |> Credo.Code.ast() |> uses_of_preceding_aliases()

    source_file
    |> StrictModuleLayout.run(params)
    |> Enum.reject(&(&1.message == @use_after_alias and &1.line_no in exempt_lines))
  end

  # Lines of `use` expressions whose arguments reference an alias declared
  # earlier in the same module body.
  defp uses_of_preceding_aliases(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:defmodule, _, [_name, [{_do, body}]]} = node, acc ->
          {node, MapSet.union(acc, exempt_in_body(body))}

        node, acc ->
          {node, acc}
      end)

    lines
  end

  defp exempt_in_body(body) do
    body
    |> body_exprs()
    |> Enum.reduce({MapSet.new(), MapSet.new()}, fn
      {:alias, _, args}, {aliases, lines} ->
        {MapSet.union(aliases, alias_names(args)), lines}

      {:use, meta, args}, {aliases, lines} ->
        case references_any?(args, aliases) do
          true -> {aliases, MapSet.put(lines, meta[:line])}
          false -> {aliases, lines}
        end

      _expr, acc ->
        acc
    end)
    |> elem(1)
  end

  defp body_exprs({:__block__, _, exprs}), do: exprs
  defp body_exprs(expr), do: [expr]

  defp alias_names([_target, opts]) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [name]} -> MapSet.new([name])
      _ -> MapSet.new()
    end
  end

  defp alias_names([{{:., _, [_base, :{}]}, _, children}]) do
    children
    |> Enum.flat_map(fn {:__aliases__, _, parts} -> [List.last(parts)] end)
    |> MapSet.new()
  end

  defp alias_names([{:__aliases__, _, parts}]), do: MapSet.new([List.last(parts)])
  defp alias_names(_args), do: MapSet.new()

  defp references_any?(args, aliases) do
    {_ast, found?} =
      Macro.prewalk(args, false, fn
        {:__aliases__, _, [first | _]} = node, acc -> {node, acc or first in aliases}
        node, acc -> {node, acc}
      end)

    found?
  end
end
