defmodule Chat.Data.ReviewPasswordCandidate.Promotion do
  @moduledoc """
  Two-phase candidate promotion for all moderation modes.

  Phase 1 (promote_candidate): server validates candidates, wraps rights
  (unsigned) into right candidate tables, returns shared_secrets.

  Phase 2 (complete_promotion): after author signs the right candidates,
  server verifies signatures and promotes everything to real tables.

  Exception: :none mode is single-phase — auto-promotes immediately.
  """

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Integrity
  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPostRightCandidate
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Schemas.ReviewRevokeRightCandidate
  alias EnigmaPq

  # --- Phase 1: Server wraps candidates into unsigned right candidates ---

  def promote_candidate(%ReviewPasswordCandidate{} = candidate) do
    with %{origin_hash: origin_hash} <- ReviewData.get_review(candidate.review_hash),
         %{moderation_mode: mode} <- OriginData.get_origin(origin_hash) do
      promote_by_mode(mode, candidate, origin_hash)
    else
      _ -> {:error, "review or origin not found"}
    end
  end

  # --- Phase 2: Author signed right candidates, verify and promote ---

  def complete_promotion(review_hash) do
    with %{origin_hash: origin_hash} <- ReviewData.get_review(review_hash),
         %{moderation_mode: mode} <- OriginData.get_origin(origin_hash) do
      complete_by_mode(mode, review_hash, origin_hash)
    else
      _ -> {:error, "review or origin not found"}
    end
  end

  # --- Phase 1 internals ---

  defp promote_by_mode(:none, candidate, _origin_hash) do
    promote_none(candidate)
  end

  defp promote_by_mode(:post, candidate, origin_hash) do
    promote_post(candidate, origin_hash)
  end

  defp promote_by_mode(:pre, candidate, origin_hash) do
    promote_pre(candidate, origin_hash)
  end

  defp promote_none(candidate) do
    %ReviewPublicPassword{}
    |> ReviewPublicPassword.create_changeset(%{
      review_hash: candidate.review_hash,
      sign_hash: candidate.sign_hash,
      origin_hash: candidate.origin_hash,
      password_b64: candidate.password_b64,
      author_hash: candidate.author_hash,
      deleted_flag: false,
      owner_timestamp: candidate.owner_timestamp,
      sign_b64: candidate.sign_b64
    })
    |> repo().insert(
      on_conflict: :nothing,
      conflict_target: [:review_hash, :sign_hash],
      allow_stale: true
    )
  end

  defp promote_post(candidate, origin_hash) do
    with {:card, %{crypt_pkey: pkey}} <- {:card, user_card(origin_hash)},
         {:null, %{} = null_c} <-
           {:null, find_null_candidate(candidate.review_hash, candidate.author_hash)} do
      {shared_secret, kem_ct, wrapped} = wrap_candidate_for_origin(null_c, pkey)

      %ReviewRevokeRightCandidate{}
      |> ReviewRevokeRightCandidate.create_changeset(
        right_candidate_attrs(candidate, origin_hash, kem_ct, wrapped)
      )
      |> RightCandidateData.insert_revoke_candidate()
      |> then(fn
        {:ok, _} -> {:ok, %{revoke_shared_secret: shared_secret}}
        error -> error
      end)
    else
      {:card, _} -> {:error, "origin card not found"}
      {:null, nil} -> {:error, "null candidate required for post mode"}
    end
  end

  defp promote_pre(candidate, origin_hash) do
    with {:card, %{crypt_pkey: pkey}} <- {:card, user_card(origin_hash)},
         {:pwd, %{} = pwd_c} <-
           {:pwd, find_password_candidate(candidate.review_hash, candidate.author_hash)},
         {:null, %{} = null_c} <-
           {:null, find_null_candidate(candidate.review_hash, candidate.author_hash)} do
      {post_secret, post_kem, post_wrapped} = wrap_candidate_for_origin(pwd_c, pkey)
      {revoke_secret, revoke_kem, revoke_wrapped} = wrap_candidate_for_origin(null_c, pkey)

      post_result =
        %ReviewPostRightCandidate{}
        |> ReviewPostRightCandidate.create_changeset(
          right_candidate_attrs(candidate, origin_hash, post_kem, post_wrapped)
        )
        |> RightCandidateData.insert_post_candidate()

      revoke_result =
        %ReviewRevokeRightCandidate{}
        |> ReviewRevokeRightCandidate.create_changeset(
          right_candidate_attrs(candidate, origin_hash, revoke_kem, revoke_wrapped)
        )
        |> RightCandidateData.insert_revoke_candidate()

      with {:ok, _} <- post_result,
           {:ok, _} <- revoke_result do
        {:ok, %{post_shared_secret: post_secret, revoke_shared_secret: revoke_secret}}
      end
    else
      {:card, _} -> {:error, "origin card not found"}
      {:pwd, nil} -> {:error, "password candidate required for pre mode"}
      {:null, nil} -> {:error, "null candidate required for pre mode"}
    end
  end

  # --- Phase 2 internals ---

  defp complete_by_mode(:none, _review_hash, _origin_hash) do
    {:error, "complete_promotion not applicable for :none mode"}
  end

  defp complete_by_mode(:post, review_hash, _origin_hash) do
    with {:revoke, %{sign_b64: sign_b64} = rc} when not is_nil(sign_b64) <-
           {:revoke, RightCandidateData.get_revoke_candidate(review_hash)},
         {:sig, :ok} <- {:sig, verify_right_candidate_signature(rc)},
         {:pwd, %{} = pwd_c} <-
           {:pwd, find_password_candidate(review_hash, rc.author_hash)} do
      repo().transaction(fn ->
        {:ok, _} = promote_right(rc, ReviewRevokeRight, &RevokeRightData.upsert_revoke_right/1)
        {:ok, _} = promote_password_candidate(pwd_c)

        RightCandidateData.delete_candidates_for_review(review_hash)
        delete_password_candidates(review_hash)
      end)
    else
      {:revoke, nil} -> {:error, "revoke right candidate not found"}
      {:revoke, %{sign_b64: nil}} -> {:error, "revoke right candidate not signed"}
      {:sig, {:error, reason}} -> {:error, reason}
      {:pwd, nil} -> {:error, "password candidate not found"}
    end
  end

  defp complete_by_mode(:pre, review_hash, _origin_hash) do
    with {:post, %{sign_b64: post_sign} = pc} when not is_nil(post_sign) <-
           {:post, RightCandidateData.get_post_candidate(review_hash)},
         {:revoke, %{sign_b64: revoke_sign} = rc} when not is_nil(revoke_sign) <-
           {:revoke, RightCandidateData.get_revoke_candidate(review_hash)},
         {:post_sig, :ok} <- {:post_sig, verify_right_candidate_signature(pc)},
         {:revoke_sig, :ok} <- {:revoke_sig, verify_right_candidate_signature(rc)} do
      repo().transaction(fn ->
        {:ok, _} = promote_right(pc, ReviewPostRight, &PostRightData.upsert_post_right/1)
        {:ok, _} = promote_right(rc, ReviewRevokeRight, &RevokeRightData.upsert_revoke_right/1)

        RightCandidateData.delete_candidates_for_review(review_hash)
        delete_password_candidates(review_hash)
      end)
    else
      {:post, nil} -> {:error, "post right candidate not found"}
      {:post, %{sign_b64: nil}} -> {:error, "post right candidate not signed"}
      {:revoke, nil} -> {:error, "revoke right candidate not found"}
      {:revoke, %{sign_b64: nil}} -> {:error, "revoke right candidate not signed"}
      {:post_sig, {:error, reason}} -> {:error, reason}
      {:revoke_sig, {:error, reason}} -> {:error, reason}
    end
  end

  # --- Shared helpers ---

  defp right_candidate_attrs(candidate, origin_hash, kem_ct, wrapped) do
    %{
      review_hash: candidate.review_hash,
      origin_hash: origin_hash,
      author_hash: candidate.author_hash,
      kem_ciphertext_b64: kem_ct,
      wrapped_row_b64: wrapped,
      deleted_flag: false,
      owner_timestamp: candidate.owner_timestamp,
      inserted_at: System.os_time(:millisecond)
    }
  end

  defp promote_right(right_candidate, schema, upsert_fn) do
    struct(schema)
    |> schema.create_changeset(%{
      review_hash: right_candidate.review_hash,
      origin_hash: right_candidate.origin_hash,
      author_hash: right_candidate.author_hash,
      kem_ciphertext_b64: right_candidate.kem_ciphertext_b64,
      wrapped_row_b64: right_candidate.wrapped_row_b64,
      deleted_flag: right_candidate.deleted_flag,
      owner_timestamp: right_candidate.owner_timestamp,
      sign_b64: right_candidate.sign_b64,
      sign_hash: right_candidate.sign_hash
    })
    |> upsert_fn.()
  end

  defp promote_password_candidate(candidate) do
    %ReviewPublicPassword{}
    |> ReviewPublicPassword.create_changeset(%{
      review_hash: candidate.review_hash,
      sign_hash: candidate.sign_hash,
      origin_hash: candidate.origin_hash,
      password_b64: candidate.password_b64,
      author_hash: candidate.author_hash,
      deleted_flag: false,
      owner_timestamp: candidate.owner_timestamp,
      sign_b64: candidate.sign_b64
    })
    |> PublicPasswordData.upsert_review_public_password()
  end

  defp verify_right_candidate_signature(right_candidate) do
    Integrity.verify_signature(right_candidate)
  end

  defp find_null_candidate(review_hash, author_hash) do
    review_hash
    |> CandidateData.get_candidates_for_review()
    |> Enum.find(fn c -> c.author_hash == author_hash and is_nil(c.password_b64) end)
  end

  defp find_password_candidate(review_hash, author_hash) do
    review_hash
    |> CandidateData.get_candidates_for_review()
    |> Enum.find(fn c -> c.author_hash == author_hash and not is_nil(c.password_b64) end)
  end

  defp delete_password_candidates(review_hash) do
    import Ecto.Query

    Chat.Data.Schemas.ReviewPasswordCandidate
    |> where([c], c.review_hash == ^review_hash)
    |> repo().delete_all()
  end

  defp wrap_candidate_for_origin(candidate, origin_crypt_pkey) do
    row_data =
      Jason.encode!(%{
        review_hash: candidate.review_hash,
        sign_hash: candidate.sign_hash,
        origin_hash: candidate.origin_hash,
        password_b64:
          if(candidate.password_b64, do: Base.encode64(candidate.password_b64, padding: false)),
        author_hash: candidate.author_hash,
        deleted_flag: false,
        owner_timestamp: candidate.owner_timestamp,
        sign_b64: Base.encode64(candidate.sign_b64, padding: false)
      })

    {shared_secret, kem_ct} = EnigmaPq.encapsulate_secret(origin_crypt_pkey)
    wrap_key = EnigmaPq.hkdf_derive(shared_secret, "buckitup/review-right/v1", "wrap")
    wrapped = EnigmaPq.aes_gcm_encrypt(row_data, wrap_key)

    {shared_secret, kem_ct, wrapped}
  end

  defp user_card(hash) do
    Chat.Data.User.get_card(hash)
  end
end
