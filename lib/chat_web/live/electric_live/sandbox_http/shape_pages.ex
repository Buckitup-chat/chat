defmodule ChatWeb.ElectricLive.SandboxHttp.ShapePages do
  @moduledoc """
  One-shot shape reads over `GET /electric/v1/shapes`: follows pagination and
  folds the shape log by row key (inserts/updates upsert, deletes remove).
  """

  @doc "Shape URL for `table`, optionally filtered by a `where` clause."
  def shape_url(base_url, table, nil),
    do: "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1"

  def shape_url(base_url, table, where),
    do: "#{base_url}/electric/v1/shapes?table=#{table}&offset=-1&where=#{URI.encode(where)}"

  @doc """
  Fetches every page of the shape at `url`.

  Returns `{:ok, rows}`, `{:error, {status, body, resp_headers}}` or `{:error, reason}`.
  """
  def fetch_pages(url, headers, acc) do
    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body, headers: rh}} ->
        rows = fold_operations(acc, body)

        if up_to_date?(body) do
          {:ok, Map.values(rows)}
        else
          fetch_pages(next_page_url(url, rh), headers, rows)
        end

      {:ok, %{status: 204}} ->
        {:ok, Map.values(acc)}

      {:ok, %{status: s, body: b, headers: rh}} ->
        {:error, {s, b, rh}}

      {:error, e} ->
        {:error, e}
    end
  end

  defp up_to_date?(body) when is_list(body) do
    Enum.any?(body, &match?(%{"headers" => %{"control" => "up-to-date"}}, &1))
  end

  defp up_to_date?(_), do: true

  defp next_page_url(url, resp_headers) do
    [offset | _] = resp_headers["electric-offset"]
    [handle | _] = resp_headers["electric-handle"]

    url
    |> URI.parse()
    |> then(fn uri ->
      params =
        URI.decode_query(uri.query)
        |> Map.put("offset", offset)
        |> Map.put("handle", handle)

      %{uri | query: URI.encode_query(params)}
    end)
    |> URI.to_string()
  end

  defp fold_operations(acc, body) when is_list(body) do
    Enum.reduce(body, acc, fn
      %{"headers" => %{"operation" => "insert"}, "key" => key, "value" => value}, acc ->
        Map.put(acc, key, value)

      %{"headers" => %{"operation" => "update"}, "key" => key, "value" => value}, acc ->
        Map.update(acc, key, value, &Map.merge(&1, value))

      %{"headers" => %{"operation" => "delete"}, "key" => key}, acc ->
        Map.delete(acc, key)

      _, acc ->
        acc
    end)
  end

  defp fold_operations(acc, _), do: acc
end
