defmodule Support.Rewire do
  @moduledoc """
  Drop-in `import Rewire` replacement with deterministic rewired-module names.

  Rewire 0.10 names each generated module `<Target>.R<Enum.random(0..10_000)>`.
  Test files compile in parallel, so rewires of one target in different files
  collide now and then, and the later compile silently replaces the earlier
  module with the wrong mocks. Here the name is built from the caller module
  and line instead (`<Target>.Rewired.<CallerModule>.L<line>`), which is unique.

  Relies on `Rewire.Utils.parse_opts/3`, `Rewire.Alias` and `Rewire.Block`,
  internal to the `rewire` dep (pinned in mix.lock).
  """

  alias Rewire.Utils

  defmacro rewire({:__aliases__, _, module_ast}, opts) do
    module_ast
    |> parse_opts(opts, __CALLER__)
    |> Rewire.Alias.rewire_alias()
  end

  defmacro rewire({:__aliases__, _, module_ast}, opts, do: block) do
    module_ast
    |> parse_opts(opts, __CALLER__)
    |> Rewire.Block.rewire_block(block)
  end

  defp parse_opts(module_ast, opts, caller) do
    module_ast
    |> Utils.parse_opts(opts, caller)
    |> then(&%{&1 | new_module_ast: unique_module_ast(&1.old_module_ast, caller)})
  end

  defp unique_module_ast(old_module_ast, %{module: module, line: line}) do
    caller_ast = module |> Module.split() |> Enum.map(&String.to_atom/1)

    old_module_ast ++ [:Rewired | caller_ast] ++ [:"L#{line}"]
  end
end
