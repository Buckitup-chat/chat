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

  @doc """
  Folds a shape's log down to the rows it currently holds.

  For callers that build their own client and shape. Electric replays a shape it
  already has cached as a snapshot of inserts followed by every change since, so
  the log has to be folded by row key — keeping only the inserts hands back the
  row as it was before the first update it ever saw. `replica: :full` is what
  makes that fold safe: each message carries the whole row, not just the diff.
  """
  def collect(client, shape) do
    client |> Client.stream(shape, live: false, replica: :full) |> fold()
  end

  @doc "The fold `collect/2` applies, over an already-open message stream."
  def fold(messages) do
    messages
    |> Enum.reduce_while(%{}, fn
      %Message.ChangeMessage{headers: %{operation: :delete}, key: key}, acc ->
        {:cont, Map.delete(acc, key)}

      %Message.ChangeMessage{key: key, value: value}, acc ->
        {:cont, Map.put(acc, key, value)}

      %Message.ControlMessage{control: :up_to_date}, acc ->
        {:halt, acc}

      _message, acc ->
        {:cont, acc}
    end)
    |> Map.values()
  end

  defp client(base_url), do: Client.new!(endpoint: base_url <> "/electric/v1/shapes")

  defp shape(table, schema, opts) do
    opts
    |> Keyword.take([:where, :params, :columns])
    |> Keyword.put(:parser, {Client.EctoAdapter, schema})
    |> then(&Client.ShapeDefinition.new!(table, &1))
  end
end
