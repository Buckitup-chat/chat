defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Entries do
  @moduledoc """
  Turns the origin's synced rows into moderation queue entries.

  Pure: takes already-fetched shape rows plus the origin's `crypt_skey`, and
  decides for each review what the origin can read (published password, or the
  one wrapped in a not-yet-published post right) and which moderation action
  would actually change public visibility.
  """

  alias Chat.Data.ReviewRightEnvelope
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ReviewContent
  alias EnigmaPq

  def build(reviews, passwords, post_rights, revoke_rights, crypt_skey) do
    passwords_by_review = Enum.group_by(passwords, & &1.review_hash)
    post_by_review = Map.new(post_rights, &{&1.review_hash, &1})
    revoke_by_review = Map.new(revoke_rights, &{&1.review_hash, &1})

    reviews
    |> Enum.reject(& &1.deleted_flag)
    |> Enum.map(fn review ->
      build_entry(
        review,
        Map.get(passwords_by_review, review.review_hash, []),
        unwrap_right(post_by_review[review.review_hash], crypt_skey),
        unwrap_right(revoke_by_review[review.review_hash], crypt_skey)
      )
    end)
    |> Enum.sort_by(& &1.owner_timestamp, :desc)
  end

  # --- Entry ---

  defp build_entry(review, password_rows, post_right, revoke_right) do
    latest = latest_row(password_rows)

    content =
      password_rows |> available_password(post_right) |> then(&decrypt_content(review, &1))

    %{
      review_hash: review.review_hash,
      author_hash: review.author_hash,
      owner_timestamp: review.owner_timestamp,
      state: state(latest),
      latest_timestamp: latest && latest.owner_timestamp,
      post_right: post_right,
      revoke_right: revoke_right,
      password_source: password_source(password_rows, post_right),
      rating: content.rating,
      text: content.text,
      content_error: content.error,
      publish_effective?: supersedes?(post_right, latest),
      revoke_effective?: supersedes?(revoke_right, latest)
    }
  end

  defp latest_row([]), do: nil
  defp latest_row(rows), do: Enum.max_by(rows, & &1.owner_timestamp)

  defp state(nil), do: :pending
  defp state(%{password_b64: nil}), do: :hidden
  defp state(_latest), do: :public

  # Visibility is LWW by owner_timestamp: submitting a pre-signed row only
  # changes what the public sees when its timestamp beats the current latest.
  defp supersedes?(%{status: :ok, owner_timestamp: ts}, nil) when is_integer(ts), do: true

  defp supersedes?(%{status: :ok, owner_timestamp: ts}, %{owner_timestamp: latest_ts})
       when is_integer(ts) and is_integer(latest_ts),
       do: ts > latest_ts

  defp supersedes?(_right, _latest), do: false

  # The table is append-only, so a revoked review keeps its earlier password row.
  # LWW decides what the *public* sees; the origin can still read what it hid.
  defp password_source(password_rows, post_right) do
    cond do
      newest_password_row(password_rows) -> :published
      right_password(post_right) -> :post_right
      true -> nil
    end
  end

  defp available_password(password_rows, post_right) do
    case newest_password_row(password_rows) do
      %{password_b64: password} -> Crypto.decode_binary_field(password)
      nil -> right_password(post_right)
    end
  end

  defp newest_password_row(password_rows) do
    password_rows |> Enum.filter(&is_binary(&1.password_b64)) |> latest_row()
  end

  defp right_password(%{status: :ok, row: %{"password_b64" => password}})
       when is_binary(password),
       do: Crypto.decode_binary_field(password)

  defp right_password(_post_right), do: nil

  # --- Crypto ---

  defp unwrap_right(nil, _crypt_skey), do: nil

  defp unwrap_right(right, crypt_skey) do
    shared_secret =
      right.kem_ciphertext_b64
      |> Crypto.decode_binary_field()
      |> EnigmaPq.decapsulate_secret(crypt_skey)

    wrap_key = ReviewRightEnvelope.wrap_key(shared_secret)

    right.wrapped_row_b64
    |> Crypto.decode_binary_field()
    |> EnigmaPq.aes_gcm_decrypt(wrap_key)
    |> Jason.decode!()
    |> then(&%{status: :ok, row: &1, owner_timestamp: &1["owner_timestamp"], reason: nil})
  rescue
    error ->
      %{status: :error, row: nil, owner_timestamp: nil, reason: unwrap_reason(error)}
  end

  defp unwrap_reason(%Jason.DecodeError{}), do: "wrapped row is not valid JSON"
  defp unwrap_reason(_error), do: "decryption failed — not wrapped for this origin identity"

  defp decrypt_content(_review, nil), do: %{rating: nil, text: nil, error: :no_password}

  defp decrypt_content(review, password) do
    case ReviewContent.decode(review.content_b64, password) do
      {:ok, decoded} -> Map.put(decoded, :error, nil)
      :error -> %{rating: nil, text: nil, error: :undecryptable}
    end
  end
end
