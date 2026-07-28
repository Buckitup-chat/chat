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
  def rows(base_url, table, schema), do: rows(base_url, table, schema, [])

  @doc ~S"""
  Rows of `table` with options: `:where`, `:params`, `:columns`.

      rows(url, "review", Review, where: "origin_hash = $1", params: [hash])
      rows(url, "review_list", ReviewList, columns: ~w(user_hash review_hash))
  """
  def rows(base_url, table, schema, opts) when is_list(opts) do
    base_url |> client() |> collect(shape(table, schema, opts))
  end

  def rows(base_url, table, schema, where, params) do
    rows(base_url, table, schema, where: where, params: params)
  end

  defp client(base_url), do: Client.new!(endpoint: base_url <> "/electric/v1/shapes")

  defp shape(table, schema, opts) do
    opts
    |> Keyword.take([:where, :params, :columns])
    |> Keyword.put(:parser, {Client.EctoAdapter, schema})
    |> then(&Client.ShapeDefinition.new!(table, &1))
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
