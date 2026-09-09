defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ReviewLoader do
  @moduledoc """
  Reads back the reviews an author has already written for an origin.

  Outside the session that wrote it, a review's `review_password` survives only in
  the author's own `review_list` row, so only a review that reached step 5 can be
  reopened. The rest are still listed — they exist, and dropping them would make a
  later review look as if it had replaced them — carrying `review: nil` and the
  reason they cannot be opened.
  """

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList, as: ReviewListSchema
  alias ChatWeb.ElectricLive.ShapeReader
  alias EnigmaPq

  @doc """
  Every review the author wrote for `origin_hash`, newest first.

  Each item is `%{review_hash:, owner_timestamp:, review:, entry:, error:}`, where
  `review` is the decrypted review (nil when it cannot be opened) and `entry` its
  `review_list` row (nil when step 5 never ran for it).
  """
  def list_for_origin(author, origin_hash, base_url) do
    entries = list_entries(author, origin_hash, base_url)

    base_url
    |> ShapeReader.rows("review", Review, "author_hash = $1 AND origin_hash = $2", [
      author.user_hash,
      origin_hash
    ])
    |> Enum.reject(& &1.deleted_flag)
    |> Enum.sort_by(&{&1.owner_timestamp, &1.review_hash}, :desc)
    |> Enum.map(&item(&1, Map.get(entries, &1.review_hash), author))
  end

  @doc "The `sign_hash` the shape currently shows for `review_hash`."
  def current_sign_hash(review_hash, base_url) do
    base_url
    |> ShapeReader.rows("review", Review, "review_hash = $1", [review_hash])
    |> case do
      [review | _] -> {:ok, review.sign_hash}
      [] -> {:error, :not_found}
    end
  end

  defp item(row, nil, _author) do
    unopenable(row, nil, "no review_list row — this review's password is not recoverable")
  end

  defp item(row, entry, author) do
    with {:ok, password} <- decrypt_password(entry, author),
         {:ok, rating, text, content_json} <- decrypt_content(row, password) do
      %{
        review_hash: row.review_hash,
        owner_timestamp: row.owner_timestamp,
        review: review(row, password, rating, text, content_json),
        entry: entry,
        error: nil
      }
    else
      {:error, reason} -> unopenable(row, entry, reason)
    end
  end

  defp unopenable(row, entry, reason) do
    %{
      review_hash: row.review_hash,
      owner_timestamp: row.owner_timestamp,
      review: nil,
      entry: entry,
      error: reason
    }
  end

  defp review(row, password, rating, text, content_json) do
    %{
      review_hash: row.review_hash,
      origin_hash: row.origin_hash,
      review_password: password,
      rating: rating,
      text: text,
      content_json: content_json,
      owner_timestamp: row.owner_timestamp,
      parent_sign_hash: row.parent_sign_hash,
      sign_hash: row.sign_hash,
      loaded?: true
    }
  end

  # One read for the whole origin: a per-review lookup would cost a shape read each.
  defp list_entries(author, origin_hash, base_url) do
    base_url
    |> ShapeReader.rows("review_list", ReviewListSchema, "user_hash = $1 AND origin_hash = $2", [
      author.user_hash,
      origin_hash
    ])
    |> Enum.reject(& &1.deleted_flag)
    |> Enum.group_by(& &1.review_hash)
    |> Map.new(fn {hash, rows} -> {hash, Enum.max_by(rows, & &1.owner_timestamp)} end)
  end

  defp decrypt_password(entry, author) do
    entry.password_b64
    |> decode_binary()
    |> EnigmaPq.aes_gcm_decrypt(author.review_list_password)
    |> case do
      password when is_binary(password) -> {:ok, password}
      _ -> {:error, "could not decrypt review password"}
    end
  end

  defp decrypt_content(review, password) do
    review.content_b64
    |> decode_binary()
    |> EnigmaPq.aes_gcm_decrypt(password)
    |> case do
      json when is_binary(json) -> parse_content(json)
      _ -> {:error, "could not decrypt review content"}
    end
  end

  defp parse_content(json) do
    case Jason.decode(json) do
      {:ok, [rating, _placeholder, text]} -> {:ok, rating, text, json}
      _ -> {:error, "invalid review content format"}
    end
  end

  defp decode_binary(value) do
    case Base.decode64(value, padding: false) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end
end
