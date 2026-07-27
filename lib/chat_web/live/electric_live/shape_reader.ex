defmodule ChatWeb.ElectricLive.ShapeReader do
  @moduledoc """
  One-shot reads of an Electric shape over the HTTP shapes endpoint.

  Goes through `/electric/v1/shapes` rather than the embedded client so bytea
  values arrive as unpadded base64 instead of PostgreSQL's `\\x` hex — see the
  directory `CLAUDE.md`.

  `replica: :full` because callers want whole rows, not just changed columns.
  Row order is not meaningful; sort at the call site.
  """

  alias Electric.Client
  alias Electric.Client.Message

  @doc "All rows of `table`."
  def rows(base_url, table, schema) do
    base_url |> client() |> collect(shape(table, schema, nil, []))
  end

  @doc ~S"""
  Rows of `table` matching `where`, e.g. `rows(url, "review", Review, "origin_hash = $1", [hash])`.

  Keep `where` a literal with positional params — a shape definition is shared
  across every client that asks for it, so a per-reader clause re-materializes it.
  """
  def rows(base_url, table, schema, where, params) do
    base_url |> client() |> collect(shape(table, schema, where, params))
  end

  defp client(base_url), do: Client.new!(endpoint: base_url <> "/electric/v1/shapes")

  defp shape(table, schema, nil, _params) do
    Client.ShapeDefinition.new!(table, parser: {Client.EctoAdapter, schema})
  end

  defp shape(table, schema, where, params) do
    Client.ShapeDefinition.new!(table,
      where: where,
      params: params,
      parser: {Client.EctoAdapter, schema}
    )
  end

  defp collect(client, shape) do
    client
    |> Client.stream(shape, live: false, replica: :full)
    |> Enum.reduce_while([], fn
      %Message.ChangeMessage{headers: %{operation: :insert}, value: value}, acc ->
        {:cont, [value | acc]}

      %Message.ControlMessage{control: :up_to_date}, acc ->
        {:halt, acc}

      _message, acc ->
        {:cont, acc}
    end)
  end
end
