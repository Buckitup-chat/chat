defmodule Chat.Data.Types.ConstsTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.Consts

  test "every accessor is zero-arity and returns a non-empty binary" do
    for {accessor, arity} <- Consts.__info__(:functions) do
      assert arity == 0, "#{accessor}/#{arity}"
      assert <<_, _::binary>> = apply(Consts, accessor, []), "#{accessor}/0"
    end
  end

  test "current prefixes are unique strings ending with an underscore" do
    prefixes = current_accessors() |> Enum.map(&apply(Consts, &1, []))

    assert Enum.all?(prefixes, &String.ends_with?(&1, "_"))
    assert prefixes == Enum.uniq(prefixes)
  end

  test "deprecated accessors return distinct single-byte prefixes" do
    prefixes = deprecated_accessors() |> Enum.map(&apply(Consts, &1, []))

    assert [_ | _] = prefixes
    assert Enum.all?(prefixes, &(byte_size(&1) == 1))
    assert prefixes == Enum.uniq(prefixes)
  end

  # Helpers

  defp deprecated_accessors,
    do: Consts.__info__(:deprecated) |> Enum.map(fn {{accessor, 0}, _reason} -> accessor end)

  defp current_accessors,
    do: (Consts.__info__(:functions) |> Keyword.keys()) -- deprecated_accessors()
end
