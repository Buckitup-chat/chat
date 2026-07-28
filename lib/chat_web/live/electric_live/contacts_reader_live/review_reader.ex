defmodule ChatWeb.ElectricLive.ContactsReaderLive.ReviewReader do
  @moduledoc """
  Reads a user's review_list, decrypts review passwords, fetches and decrypts reviews.

  Uses trimmed columns on the review_list shape to drop the ~4.6 KB `sign_b64` per row.
  Entries with `deleted_flag` set are retracted and excluded.
  """

  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ShapeReader

  @list_columns ~w(user_hash review_hash origin_hash password_b64 deleted_flag)

  @doc """
  Reads a user's reviews via their review_list. Returns decrypted reviews grouped
  with their public visibility status.
  """
  def read(user_hash, list_password, base_url) do
    entries = fetch_review_list(user_hash, base_url)
    passwords = decrypt_list_entries(entries, list_password)
    origin_hashes = entries |> Enum.map(& &1.origin_hash) |> Enum.uniq()
    reviews = fetch_active_rows(origin_hashes, base_url, "review", Review)

    pub_passwords =
      fetch_active_rows(origin_hashes, base_url, "review_public_passwords", ReviewPublicPassword)

    {:ok,
     %{
       entries: entries,
       reviews: decrypt_reviews(reviews, passwords),
       public_passwords: build_public_password_map(pub_passwords),
       log_entries: []
     }}
  end

  @doc "Decrypts a review's content with the given key. Returns a map or nil."
  def decrypt_review_content(review, review_password) do
    with content when is_binary(content) <- Crypto.decode_binary_field(review.content_b64),
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

  @doc "Groups public passwords by review_hash, returning `%{hash => has_password?}`."
  def build_public_password_map(passwords) do
    passwords
    |> Enum.group_by(& &1.review_hash)
    |> Map.new(fn {hash, entries} ->
      latest = Enum.max_by(entries, & &1.owner_timestamp)
      {hash, latest.password_b64 != nil}
    end)
  end

  defp fetch_review_list(user_hash, base_url) do
    ShapeReader.rows(base_url, "review_list", ReviewList,
      where: "user_hash = $1",
      params: [user_hash],
      columns: @list_columns
    )
    |> Enum.reject(& &1.deleted_flag)
  end

  defp decrypt_list_entries(entries, list_password) do
    entries
    |> Enum.flat_map(fn entry ->
      case decrypt_password(entry.password_b64, list_password) do
        {:ok, password} -> [{entry.review_hash, password}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp decrypt_password(nil, _), do: :error
  defp decrypt_password("", _), do: :error

  defp decrypt_password(password_b64, list_password) do
    password_b64
    |> Crypto.decode_binary_field()
    |> EnigmaPq.aes_gcm_decrypt(list_password)
    |> case do
      result when is_binary(result) -> {:ok, result}
      _ -> :error
    end
  end

  defp fetch_active_rows(origin_hashes, base_url, table, schema) do
    Enum.flat_map(origin_hashes, fn origin_hash ->
      base_url
      |> ShapeReader.rows(table, schema, where: "origin_hash = $1", params: [origin_hash])
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
end
