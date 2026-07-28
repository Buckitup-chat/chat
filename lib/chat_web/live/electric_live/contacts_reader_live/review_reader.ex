defmodule ChatWeb.ElectricLive.ContactsReaderLive.ReviewReader do
  @moduledoc """
  Reads a user's review_list, decrypts review passwords, fetches and decrypts reviews.

  Uses trimmed columns (`user_hash,review_hash,origin_hash,password_b64,deleted_flag`) on the
  review_list shape to drop the ~4.6 KB `sign_b64` per row. Entries with `deleted_flag` set
  are retracted and excluded.
  """

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.ShapeReader
  alias EnigmaPq

  @list_columns "user_hash,review_hash,origin_hash,password_b64,deleted_flag"

  @doc """
  Reads a user's reviews via their review_list. Returns decrypted reviews grouped
  with their public visibility status.
  """
  def read(user_hash, list_password, base_url) do
    with {:ok, entries, list_log} <- fetch_review_list(user_hash, base_url) do
      passwords = decrypt_list_entries(entries, list_password)
      origin_hashes = entries |> Enum.map(& &1["origin_hash"]) |> Enum.uniq()
      reviews = fetch_active_rows(origin_hashes, base_url, "review", Review)

      pub_passwords =
        fetch_active_rows(
          origin_hashes,
          base_url,
          "review_public_passwords",
          ReviewPublicPassword
        )

      {:ok,
       %{
         entries: entries,
         reviews: decrypt_reviews(reviews, passwords),
         public_passwords: build_public_password_map(pub_passwords),
         log_entries: list_log
       }}
    end
  end

  defp fetch_review_list(user_hash, base_url) do
    url =
      "#{base_url}/electric/v1/shapes?table=review_list" <>
        "&where=user_hash%3D%27#{user_hash}%27" <>
        "&columns=#{@list_columns}" <>
        "&offset=-1"

    timestamp = TimeKeeper.now()

    case Req.get(url, headers: [{"accept", "application/json"}]) do
      {:ok, %{status: 200, body: body} = resp} ->
        {:ok, parse_shape_rows(body), [log_entry("GET", url, resp, timestamp)]}

      {:ok, %{status: status} = resp} ->
        {:error, "review_list fetch failed: #{status} — #{inspect(resp.body)}"}

      {:error, reason} ->
        {:error, "review_list fetch failed: #{inspect(reason)}"}
    end
  end

  defp parse_shape_rows(body) when is_list(body) do
    body
    |> Enum.filter(&match?(%{"headers" => %{"operation" => "insert"}}, &1))
    |> Enum.map(& &1["value"])
    |> Enum.reject(& &1["deleted_flag"])
  end

  defp parse_shape_rows(_), do: []

  defp log_entry(method, url, resp, timestamp) do
    %{
      timestamp: timestamp,
      method: method,
      url: url,
      request_headers: [{"accept", "application/json"}],
      request_body: "",
      response_status: resp.status,
      response_headers: resp_headers(resp.headers),
      response_body:
        if(is_map(resp.body) or is_list(resp.body),
          do: Jason.encode!(resp.body, pretty: true),
          else: inspect(resp.body)
        )
    }
  end

  defp resp_headers(headers) when is_map(headers),
    do: Enum.map(headers, fn {k, v} -> {k, Enum.join(v, ", ")} end)

  defp resp_headers(headers) when is_list(headers), do: headers

  defp decrypt_list_entries(entries, list_password) do
    entries
    |> Enum.flat_map(fn %{"review_hash" => hash, "password_b64" => password_b64} ->
      case decrypt_password(password_b64, list_password) do
        {:ok, password} -> [{hash, password}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp decrypt_password(nil, _), do: :error
  defp decrypt_password("", _), do: :error

  defp decrypt_password(password_b64, list_password) do
    password_b64
    |> decode_binary()
    |> EnigmaPq.aes_gcm_decrypt(list_password)
    |> case do
      result when is_binary(result) -> {:ok, result}
      _ -> :error
    end
  end

  defp fetch_active_rows(origin_hashes, base_url, table, schema) do
    Enum.flat_map(origin_hashes, fn origin_hash ->
      base_url
      |> ShapeReader.rows(table, schema, "origin_hash = $1", [origin_hash])
      |> Enum.reject(& &1.deleted_flag)
    end)
  end

  defp decrypt_reviews(reviews, passwords) do
    reviews
    |> Enum.flat_map(fn review ->
      case Map.get(passwords, review.review_hash) do
        nil -> []
        password -> List.wrap(decrypt_review_content(review, password))
      end
    end)
    |> Enum.sort_by(& &1.owner_timestamp, :desc)
  end

  defp decrypt_review_content(review, review_password) do
    with content when is_binary(content) <- decode_binary(review.content_b64),
         plaintext when is_binary(plaintext) <- EnigmaPq.aes_gcm_decrypt(content, review_password),
         {:ok, [rating, _placeholder, text]} <- Jason.decode(plaintext) do
      %{
        review_hash: review.review_hash,
        origin_hash: review.origin_hash,
        author_hash: review.author_hash,
        rating: rating,
        text: text,
        owner_timestamp: review.owner_timestamp
      }
    else
      _ -> nil
    end
  end

  defp build_public_password_map(passwords) do
    passwords
    |> Enum.group_by(& &1.review_hash)
    |> Map.new(fn {hash, entries} ->
      latest = Enum.max_by(entries, & &1.owner_timestamp)
      {hash, latest.password_b64 != nil}
    end)
  end

  # Shared helpers

  defp decode_binary(value) when is_binary(value) do
    case Base.decode64(value, padding: false) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  defp decode_binary(_), do: nil
end
