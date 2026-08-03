defmodule Chat.Data.ReviewPasswordCandidate.Promotion.Candidates do
  @moduledoc """
  Candidate preparation for the two-phase promotion pipeline: re-validate a
  submitted candidate on the promote node, enforce the revoke-supersedes-password
  timestamp ordering, and wrap a candidate's `review_public_passwords` row for
  the origin.
  """

  alias Chat.Data.ReviewPublicPassword.Validation, as: PublicPasswordValidation
  alias Chat.Data.ReviewRightEnvelope
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias EnigmaPq

  @doc """
  Re-validate a submitted candidate before it is minted (directly, or wrapped
  for the origin) into a `review_public_passwords` row.

  The promote node is a trust boundary that a single-server device never
  re-checks via peer replication, so it must run the same author-signature and
  author/origin binding check the peer-sync path already enforces. The candidate
  is signed over the target `review_public_passwords` payload (`deleted_flag: false`),
  so we reconstruct that row and reuse its validation verbatim.
  """
  def validate_candidate(candidate) do
    candidate
    |> ReviewPasswordCandidate.to_public_password()
    |> PublicPasswordValidation.validate_review_public_password_insert()
    |> case do
      %{valid?: true} -> :ok
      %{errors: errors} -> {:error, "invalid candidate: #{inspect(errors)}"}
    end
  end

  @doc """
  Visibility is LWW by `owner_timestamp`, so a revoke (null) row only hides a
  review when its timestamp strictly exceeds the password row's. Enforced at
  promotion time (post + pre) rather than trusting the client.
  """
  def revoke_supersedes?(null_candidate, password_candidate) do
    null_candidate.owner_timestamp > password_candidate.owner_timestamp
  end

  @doc """
  KEM-encapsulate to the origin's `crypt_pkey` and AES-GCM wrap the candidate's
  `review_public_passwords` row. Returns `{shared_secret, kem_ciphertext, wrapped}`.
  """
  def wrap_candidate_for_origin(candidate, origin_crypt_pkey) do
    row_data =
      candidate
      |> ReviewPasswordCandidate.to_public_password()
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.update!(:password_b64, &(&1 && Base.encode64(&1, padding: false)))
      |> Map.update!(:sign_b64, &Base.encode64(&1, padding: false))
      |> Jason.encode!()

    {shared_secret, kem_ct} = EnigmaPq.encapsulate_secret(origin_crypt_pkey)
    wrap_key = ReviewRightEnvelope.wrap_key(shared_secret)
    wrapped = EnigmaPq.aes_gcm_encrypt(row_data, wrap_key)

    {shared_secret, kem_ct, wrapped}
  end
end
