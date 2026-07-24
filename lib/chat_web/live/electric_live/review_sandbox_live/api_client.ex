defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient do
  @moduledoc "API client for review sandbox: all operations via HTTP."

  import ChatWeb.ElectricLive.ReviewSandboxLive.Http

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewListSignHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.TimeKeeper
  alias EnigmaPq

  def submit_review(author, origin_hash, content, base_url) do
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    review_password = :crypto.strong_rand_bytes(32)
    content_b64 = EnigmaPq.aes_gcm_encrypt(content, review_password)
    timestamp = TimeKeeper.now_unix()

    review_struct = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author.user_hash,
      content_b64: content_b64,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: timestamp
    }

    {sign_b64, sign_hash} = sign_struct(review_struct, author.sign_skey, ReviewSignHash)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "review_hash" => review_hash,
            "origin_hash" => origin_hash,
            "author_hash" => author.user_hash,
            "content_b64" => encode_base64(content_b64),
            "deleted_flag" => false,
            "owner_timestamp" => timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "review"}
        }
      ]
    }

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      review_data = %{
        review_hash: review_hash,
        origin_hash: origin_hash,
        review_password: review_password,
        content: content,
        owner_timestamp: timestamp
      }

      {:ok, %{review: review_data, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def submit_review_list_entry(author, review, proof_fields, base_url) do
    timestamp = TimeKeeper.now_unix()
    encrypted_pwd = EnigmaPq.aes_gcm_encrypt(review.review_password, author.review_list_password)

    rl_struct = %ReviewList{
      user_hash: author.user_hash,
      review_hash: review.review_hash,
      password_b64: encrypted_pwd,
      review_password_sign_hash: proof_fields[:review_password_sign_hash],
      post_right_sign_hash: proof_fields[:post_right_sign_hash],
      revoke_right_sign_hash: proof_fields[:revoke_right_sign_hash],
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    {sign_b64, sign_hash} = sign_struct(rl_struct, author.sign_skey, ReviewListSignHash)

    modified =
      %{
        "user_hash" => author.user_hash,
        "review_hash" => review.review_hash,
        "password_b64" => encode_base64(encrypted_pwd),
        "deleted_flag" => false,
        "owner_timestamp" => timestamp,
        "sign_b64" => encode_base64(sign_b64),
        "sign_hash" => sign_hash
      }
      |> put_if("review_password_sign_hash", proof_fields[:review_password_sign_hash])
      |> put_if("post_right_sign_hash", proof_fields[:post_right_sign_hash])
      |> put_if("revoke_right_sign_hash", proof_fields[:revoke_right_sign_hash])

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => modified,
          "syncMetadata" => %{"relation" => "review_list"}
        }
      ]
    }

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      {:ok, %{log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def submit_password_candidates(author, review, base_url) do
    origin_hash = review.origin_hash
    base_ts = review.owner_timestamp + 100_000
    pwd_mutation = build_candidate_mutation(author, origin_hash, review, :password, base_ts)
    null_mutation = build_candidate_mutation(author, origin_hash, review, :null, base_ts + 1)
    payload = %{"mutations" => [pwd_mutation, null_mutation]}

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      candidates = read_right_candidates(review.review_hash)
      shared_secrets = extract_shared_secrets(resp)
      {:ok, %{candidates: candidates, shared_secrets: shared_secrets, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def sign_right_candidates(author, candidates, shared_secrets, review, base_url) do
    with :ok <- verify_wrapping(candidates, shared_secrets, review, author) do
      mutations =
        [candidates.post, candidates.revoke]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&build_right_sign_mutation(&1, author))

      with {:ok, ch, log1} <- get_challenge(base_url),
           {:ok, _resp, log2} <-
             post_ingest(ch, %{"mutations" => mutations}, author.sign_skey, base_url) do
        {:ok, %{log_entries: [log1, log2]}}
      else
        {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
      end
    else
      {:error, reason} -> {:error, %{reason: reason, log_entries: []}}
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp read_right_candidates(review_hash) do
    %{
      post: RightCandidateData.get_post_candidate(review_hash),
      revoke: RightCandidateData.get_revoke_candidate(review_hash)
    }
  end

  defp build_candidate_mutation(author, origin_hash, review, type, timestamp) do
    password_b64 = if type == :password, do: review.review_password

    signable = %ReviewPublicPassword{
      review_hash: review.review_hash,
      sign_hash: nil,
      origin_hash: origin_hash,
      password_b64: password_b64,
      author_hash: author.user_hash,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    {sign_b64, sign_hash} = sign_struct(signable, author.sign_skey, ReviewPasswordSignHash)

    modified =
      %{
        "review_hash" => review.review_hash,
        "sign_hash" => sign_hash,
        "origin_hash" => origin_hash,
        "author_hash" => author.user_hash,
        "owner_timestamp" => timestamp,
        "sign_b64" => encode_base64(sign_b64)
      }
      |> put_if("password_b64", if(password_b64, do: encode_base64(password_b64)))

    %{
      "type" => "insert",
      "modified" => modified,
      "syncMetadata" => %{"relation" => "review_password_candidate"}
    }
  end

  defp build_right_sign_mutation(candidate, author) do
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    {sign_hash, relation} = right_candidate_meta(candidate, sign_b64)

    %{
      "type" => "update",
      "original" => %{"review_hash" => candidate.review_hash},
      "changes" => %{
        "sign_b64" => encode_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => relation}
    }
  end

  defp right_candidate_meta(%ReviewPostRightCandidate{}, sign_b64) do
    {sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary(),
     "review_post_right_candidate"}
  end

  defp right_candidate_meta(%ReviewRevokeRightCandidate{}, sign_b64) do
    {sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary(),
     "review_revoke_right_candidate"}
  end

  defp extract_shared_secrets(%{headers: headers}) do
    %{}
    |> put_decoded_header(headers, "x-review-post-shared-secret", :post_shared_secret)
    |> put_decoded_header(headers, "x-review-revoke-shared-secret", :revoke_shared_secret)
  end

  defp put_decoded_header(acc, headers, name, key) do
    case headers do
      %{^name => [value | _]} -> Map.put(acc, key, Base.decode64!(value, padding: false))
      _ -> acc
    end
  end

  @wrap_context "buckitup/review-right/v1"
  @wrap_label "wrap"

  defp verify_wrapping(candidates, shared_secrets, review, author) do
    with :ok <-
           verify_candidate(
             candidates.post,
             shared_secrets[:post_shared_secret],
             review,
             author,
             :post
           ),
         :ok <-
           verify_candidate(
             candidates.revoke,
             shared_secrets[:revoke_shared_secret],
             review,
             author,
             :revoke
           ) do
      :ok
    end
  end

  defp verify_candidate(nil, _secret, _review, _author, _type), do: :ok

  defp verify_candidate(_candidate, nil, _review, _author, _type),
    do: {:error, "missing shared secret for right candidate verification"}

  defp verify_candidate(candidate, shared_secret, review, author, type) do
    wrap_key = EnigmaPq.hkdf_derive(shared_secret, @wrap_context, @wrap_label)

    case EnigmaPq.aes_gcm_decrypt(candidate.wrapped_row_b64, wrap_key) do
      :error ->
        {:error, "wrapped content decryption failed — server may have tampered"}

      row_json ->
        row_json |> Jason.decode!() |> verify_row_fields(review, author, type)
    end
  end

  defp verify_row_fields(row, review, author, type) do
    cond do
      row["review_hash"] != review.review_hash ->
        {:error, "wrapped review_hash does not match submitted review"}

      row["author_hash"] != author.user_hash ->
        {:error, "wrapped author_hash does not match author identity"}

      type == :revoke and row["password_b64"] != nil ->
        {:error, "revoke right wraps non-null password"}

      type == :post and row["password_b64"] != encode_base64(review.review_password) ->
        {:error, "post right password does not match review password"}

      true ->
        :ok
    end
  end
end
