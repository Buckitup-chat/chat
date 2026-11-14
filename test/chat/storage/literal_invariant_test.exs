defmodule Chat.Storage.LiteralInvariantTest do
  @moduledoc """
  Storage Units spec §5 invariant 1: path segments, the CubDB version and link
  names live only in `Chat.Storage.Unit`, `Role` and `Link`.

  Scans string literals in the code (not docs or comments) of chat's `lib/` and,
  when checked out next to chat, platform's `lib/`.
  """
  use ExUnit.Case, async: true

  alias Chat.Storage.Role
  alias Chat.Storage.Unit

  @platform_lib Path.expand("../platform/lib", File.cwd!())

  @allowed [
    "lib/chat/storage/unit.ex",
    "lib/chat/storage/role.ex",
    "lib/chat/storage/link.ex",
    # One-time relocation of the pre-unit layout; removed once the fleet is migrated
    Path.join(@platform_lib, "platform/storage/pq_reset.ex")
  ]

  @doc_attrs [:doc, :moduledoc, :typedoc, :shortdoc]

  test "storage literals appear only in Unit, Role and Link" do
    offenses =
      lib_files()
      |> Enum.reject(&(&1 in @allowed))
      |> Enum.flat_map(fn file -> file |> File.read!() |> offenses() |> Enum.map(&{file, &1}) end)

    assert [] == offenses, """
    Storage literals outside Chat.Storage.Unit / Role / Link.
    Derive them via Unit.path/2, Role.dir/1 or Link.name/2 instead:

    #{Enum.map_join(offenses, "\n", fn {file, {line, literal}} -> "  #{file}:#{line} #{inspect(literal)}" end)}
    """
  end

  test "a literal added elsewhere is caught" do
    assert [{3, "pq_files"}] = offenses(~s|defmodule X do\n  def a,\n    do: "pq_files"\nend|)
    assert [{1, "main_from_internal"}] = offenses(~S|x = "main_from_internal"|)
    assert [{1, "backup_db"}] = offenses(~s|Path.join(["\#{root}", "backup_db"])|)
    assert [{1, _}] = offenses(~s|Path.join(root, "#{Unit.cub_version()}")|)
    assert [{1, "_files"}] = offenses(~s|"\#{dir}" <> "_files"|)
  end

  test "docs, comments and unrelated strings are not offenses" do
    assert [] = offenses(~s|@moduledoc "pq_files"\n@doc "main_from_internal"|)
    assert [] = offenses(~s|# "pq_files"\nx = "back_to_origins"|)
    assert [] = offenses(~S|x = "pg_dump"|)
  end

  defp lib_files do
    platform = if File.dir?(@platform_lib), do: [@platform_lib], else: []

    ["lib" | platform]
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
  end

  defp offenses(source) do
    source
    |> Code.string_to_quoted!(literal_encoder: &{:ok, {:__block__, &2, [&1]}})
    |> Macro.prewalk([], fn
      {:@, _, [{attr, _, _}]}, acc when attr in @doc_attrs ->
        {nil, acc}

      {:__block__, meta, [literal]} = node, acc when is_binary(literal) ->
        {node, collect(acc, meta, literal)}

      {:<<>>, meta, parts} = node, acc ->
        {node, parts |> Enum.filter(&is_binary/1) |> Enum.reduce(acc, &collect(&2, meta, &1))}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect(acc, meta, literal) do
    if forbidden?(literal), do: [{Keyword.get(meta, :line), literal} | acc], else: acc
  end

  defp forbidden?(literal) do
    literal in forbidden_literals() or Regex.match?(~r/^v\.\d+\.\d+$/, literal)
  end

  defp forbidden_literals do
    roles = Role.all()
    role_dirs = for role <- roles, role != :internal, do: Role.dir(role)

    link_names =
      for from <- roles,
          to <- roles,
          from != to,
          name <- ["#{from}_to_#{to}", "#{to}_from_#{from}"],
          do: name

    ["pg", "pq_files", "_files", "_db", Unit.cub_version()] ++ role_dirs ++ link_names
  end
end
