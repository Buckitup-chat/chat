defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient do
  @moduledoc "API client for review sandbox: all operations via HTTP."

  import ChatWeb.ElectricLive.ReviewSandboxLive.Http

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Verification
  alias EnigmaPq

  def submit_review(author, origin_hash, rating, text, base_url) do
    content = review_content(rating, text)
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
        #AI: see 2 lines bellow. arent' this a part of content ? where this is used ?
        rating: rating,
        text: text,
        content_json: content,
        owner_timestamp: timestamp
      }

      {:ok, %{review: review_data, log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  # `[rating, placeholder, content]` — the placeholder pads a rating-only review
  # so its ciphertext size does not give away that no text was written.
  defp review_content(rating, "") do
    placeholder = 20..200 |> Enum.random() |> :crypto.strong_rand_bytes()
    Jason.encode!([rating, Base.url_encode64(placeholder, padding: false), ""])
  end

  defp review_content(rating, text), do: Jason.encode!([rating, "", text])

  # The candidate's own sign_hash is what the server copies verbatim into
  # review_public_passwords on promotion, so capturing it here is the author's
  # only durable handle on the promotion proof: pre mode deletes the candidate
  # once the rights are signed, and ML-DSA-87 signing is randomized, so it cannot
  # be recomputed later.
  def submit_password_candidates(author, review, base_url) do
    origin_hash = review.origin_hash
    base_ts = review.owner_timestamp + 100_000

    {pwd_mutation, pwd_sign_hash} =
      candidate_mutation(author, origin_hash, review, :password, base_ts)

    {null_mutation, _null_sign_hash} =
      candidate_mutation(author, origin_hash, review, :null, base_ts + 1)

    payload = %{"mutations" => [pwd_mutation, null_mutation]}

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, resp, log2} <- post_ingest(ch, payload, author.sign_skey, base_url) do
      candidates = read_right_candidates(review.review_hash)
      shared_secrets = Verification.extract_shared_secrets(resp)

      {:ok,
       %{
         candidates: candidates,
         shared_secrets: shared_secrets,
         review_password_sign_hash: pwd_sign_hash,
         log_entries: [log1, log2]
       }}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def sign_right_candidates(author, candidates, shared_secrets, review, base_url) do
    case Verification.verify_wrapping(candidates, shared_secrets, review, author) do
      :ok -> post_right_signatures(author, candidates, base_url)
      {:error, reason} -> {:error, %{reason: reason, log_entries: []}}
    end
  end

  defp post_right_signatures(author, candidates, base_url) do
    signed =
      [candidates.post, candidates.revoke]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&right_sign_mutation(&1, author))

    mutations = Enum.map(signed, &elem(&1, 0))
    hashes = signed |> Enum.map(&elem(&1, 1)) |> Map.new()

    with {:ok, ch, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <-
           post_ingest(ch, %{"mutations" => mutations}, author.sign_skey, base_url) do
      {:ok, Map.merge(hashes, %{log_entries: [log1, log2]})}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
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

  defp candidate_mutation(author, origin_hash, review, type, timestamp) do
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

    mutation = %{
      "type" => "insert",
      "modified" => modified,
      "syncMetadata" => %{"relation" => "review_password_candidate"}
    }

    {mutation, sign_hash}
  end

  # Returns the mutation plus `{slot, sign_hash}` — the same sign_hash the server
  # carries over into review_post_right / review_revoke_right on promotion, and
  # therefore the value review_list must reference as its moderation proof.
  defp right_sign_mutation(candidate, author) do
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    {sign_hash, relation, slot} = right_candidate_meta(candidate, sign_b64)

    mutation = %{
      "type" => "update",
      "original" => %{"review_hash" => candidate.review_hash},
      "changes" => %{
        "sign_b64" => encode_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => relation}
    }

    {mutation, {slot, sign_hash}}
  end

  defp right_candidate_meta(%ReviewPostRightCandidate{}, sign_b64) do
    {sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary(),
     "review_post_right_candidate", :post_right_sign_hash}
  end

  defp right_candidate_meta(%ReviewRevokeRightCandidate{}, sign_b64) do
    {sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary(),
     "review_revoke_right_candidate", :revoke_right_sign_hash}
  end
end
