defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList do
  @moduledoc """
  The author's `review_list` row — the contacts channel's server-side half.

  One row per review, holding the `review_password` encrypted under the
  per-author `review_list_password` (see `ListPassword`), gated by the origin's
  moderation-proof matrix (see `ReviewList.Proofs`).

  Pre mode needs two writes: the insert carries no promotion proof because the
  review is not public yet, and the author fills `review_password_sign_hash` in
  by update once the origin approves.
  """

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList.Proofs
  alias EnigmaPq

  # --- Reading what the server actually promoted ---

  @doc """
  The `sign_hash` of each proof row as the shapes currently show it, or nil.

  A nil means "not observed", never "rejected" — Electric lags the commit the
  server validates against. See `Proofs`.
  """
  def load_proofs(review, base_url, auth) do
    %{
      review_password_sign_hash: observed_password_hash(review, base_url, auth),
      post_right_sign_hash: observed_right_hash(review, base_url, "review_post_right", auth),
      revoke_right_sign_hash: observed_right_hash(review, base_url, "review_revoke_right", auth)
    }
  end

  defp observed_password_hash(review, base_url, auth) do
    case fetch_shape_gated(
           base_url,
           "review_public_passwords",
           "review_hash='#{review.review_hash}'",
           auth
         ) do
      {:ok, rows, _logs} ->
        rows
        |> Enum.filter(&is_binary(&1["password_b64"]))
        |> case do
          [] ->
            nil

          rows ->
            rows |> Enum.max_by(&parse_int(&1["owner_timestamp"])) |> Map.fetch!("sign_hash")
        end

      {:error, _reason, _logs} ->
        nil
    end
  end

  defp observed_right_hash(review, base_url, table, auth) do
    case fetch_shape_gated(base_url, table, "review_hash='#{review.review_hash}'", auth) do
      {:ok, rows, _logs} ->
        rows
        |> Enum.reject(&(&1["deleted_flag"] in [true, "true", "t"]))
        |> case do
          [] -> nil
          [row | _] -> row["sign_hash"]
        end

      {:error, _reason, _logs} ->
        nil
    end
  end

  # --- Writing ---

  @doc """
  Insert the row, sharing this review with the author's contacts.

  Returns the ciphertext and timestamp so a later `fill_password_proof/4` can
  sign over the merged row without re-encrypting.
  """
  def submit_entry(author, review, local_hashes, proof_fields, base_url) do
    password_b64 = EnigmaPq.aes_gcm_encrypt(review.review_password, author.review_list_password)
    owner_timestamp = TimeKeeper.now_unix()

    entry =
      %Chat.Data.Schemas.ReviewList{
        user_hash: author.user_hash,
        review_hash: review.review_hash,
        origin_hash: review.origin_hash,
        password_b64: password_b64,
        review_password_sign_hash: proof_fields[:review_password_sign_hash],
        post_right_sign_hash: proof_fields[:post_right_sign_hash],
        revoke_right_sign_hash: proof_fields[:revoke_right_sign_hash],
        deleted_flag: false,
        owner_timestamp: owner_timestamp
      }

    {sign_b64, sign_hash} = sign_struct(entry, author.sign_skey, ReviewListSignHash)

    modified =
      %{
        "user_hash" => entry.user_hash,
        "review_hash" => entry.review_hash,
        "origin_hash" => entry.origin_hash,
        "password_b64" => encode_base64(password_b64),
        "deleted_flag" => false,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => encode_base64(sign_b64),
        "sign_hash" => sign_hash
      }
      |> Map.merge(Map.new(proof_fields, fn {slot, hash} -> {to_string(slot), hash} end))

    mutation = %{
      "type" => "insert",
      "modified" => modified,
      "syncMetadata" => %{"relation" => "review_list"}
    }

    case do_ingest(mutation, author.sign_skey, base_url) do
      {:ok, logs} -> {:ok, %{entry: entry, local_hashes: local_hashes, log_entries: logs}}
      {:error, failure} -> {:error, failure}
    end
  end

  @doc """
  Pre mode: point the row at the `review_public_passwords` row the origin published.

  Only `review_password_sign_hash` and the ordering fields move — everything
  else is merged from the stored row by the server, and `origin_hash` is not
  updatable at all. The signature still has to cover the *merged* struct.
  """
  def fill_password_proof(author, entry, password_sign_hash, base_url) do
    owner_timestamp = next_timestamp(entry.owner_timestamp)

    merged = %{
      entry
      | review_password_sign_hash: password_sign_hash,
        owner_timestamp: owner_timestamp
    }

    {sign_b64, sign_hash} = sign_struct(merged, author.sign_skey, ReviewListSignHash)

    mutation = %{
      "type" => "update",
      "original" => %{"user_hash" => entry.user_hash, "review_hash" => entry.review_hash},
      "changes" => %{
        "review_password_sign_hash" => password_sign_hash,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => encode_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review_list"}
    }

    case do_ingest(mutation, author.sign_skey, base_url) do
      {:ok, logs} -> {:ok, %{entry: merged, log_entries: logs}}
      {:error, failure} -> {:error, failure}
    end
  end

  defp next_timestamp(previous), do: max(previous + 1, TimeKeeper.now_unix())

  defp do_ingest(mutation, sign_skey, base_url) do
    payload = %{"mutations" => [mutation]}

    case ingest(payload, sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, logs}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  @doc "Re-export so callers need only this module."
  defdelegate proof_fields(mode, local, status), to: Proofs, as: :fields
  defdelegate proof_status(mode, observed, local), to: Proofs, as: :status

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
