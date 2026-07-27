defmodule Chat.Test.ReviewFixtures do
  @moduledoc false

  alias Chat.Data.Integrity
  alias Chat.Data.ReviewPasswordCandidate, as: CandidateData
  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData
  alias Chat.Data.ReviewRightEnvelope
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewPublicPassword.Validation, as: PublicPasswordValidation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPasswordCandidate
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter
  alias EnigmaPq

  def insert_user_card(identity) do
    card = identity |> User.extract_pq_card() |> sign_with_key(identity.sign_skey)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  def insert_origin(origin_identity, owner, moderation_mode \\ :none) do
    origin_card = User.extract_pq_card(origin_identity)
    owner_card = User.extract_pq_card(owner)
    owner_cert = EnigmaPq.sign(origin_card.sign_pkey, owner.sign_skey)

    origin = %Origin{
      origin_hash: origin_card.user_hash,
      owner_hash: owner_card.user_hash,
      owner_cert: owner_cert,
      name: "Test Origin",
      moderation_mode: moderation_mode,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    signed = sign_with_hash(origin, origin_identity.sign_skey, &OriginSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:origin, :insert, signed)
    signed
  end

  def insert_review(author, origin_hash, opts \\ []) do
    review_hash = Keyword.get_lazy(opts, :review_hash, fn -> random_review_hash() end)
    review_password = Keyword.get_lazy(opts, :review_password, fn -> :crypto.strong_rand_bytes(32) end)
    content_b64 = Keyword.get_lazy(opts, :content_b64, fn ->
      EnigmaPq.aes_gcm_encrypt("Great coffee!", review_password)
    end)
    ts = Keyword.get(opts, :ts, System.os_time(:millisecond))
    author_hash = User.extract_pq_card(author).user_hash

    review = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author_hash,
      content_b64: content_b64,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: ts
    }

    signed = sign_with_hash(review, author.sign_skey, &ReviewSignHash.from_binary/1)
    {:ok, _} = ShapeWriter.write(:review, :insert, signed)
    Map.put(signed, :review_password, review_password)
  end

  def insert_password_candidate(author, review, origin_hash) do
    build_candidate(author, review, origin_hash, review.review_password)
  end

  def insert_null_candidate(author, review, origin_hash) do
    build_candidate(author, review, origin_hash, nil, timestamp_offset: 1)
  end

  def build_candidate(author, review, origin_hash, password_b64, opts \\ []) do
    offset = Keyword.get(opts, :timestamp_offset, 0)
    author_hash = Keyword.get(opts, :author_hash) || User.extract_pq_card(author).user_hash
    signer = Keyword.get(opts, :signer, author)
    timestamp = Keyword.get(opts, :timestamp, System.os_time(:millisecond) + offset)

    signable = %ReviewPublicPassword{
      review_hash: review.review_hash,
      sign_hash: nil,
      origin_hash: origin_hash,
      password_b64: password_b64,
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    sign_b64 = signable |> Integrity.signature_payload() |> EnigmaPq.sign(signer.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()

    changeset =
      %ReviewPasswordCandidate{}
      |> ReviewPasswordCandidate.create_changeset(%{
        review_hash: review.review_hash,
        sign_hash: sign_hash,
        origin_hash: origin_hash,
        password_b64: password_b64,
        author_hash: author_hash,
        owner_timestamp: timestamp,
        sign_b64: sign_b64
      })

    {:ok, inserted} = CandidateData.insert_candidate(changeset)
    inserted
  end

  def sign_right_candidate(:post, review_hash, author) do
    candidate = RightCandidateData.get_post_candidate(review_hash)
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPostRightSignHash.from_binary()

    {:ok, _} =
      RightCandidateData.update_candidate(candidate, %{sign_b64: sign_b64, sign_hash: sign_hash})
  end

  def sign_right_candidate(:revoke, review_hash, author) do
    candidate = RightCandidateData.get_revoke_candidate(review_hash)
    sign_b64 = candidate |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewRevokeRightSignHash.from_binary()

    {:ok, _} =
      RightCandidateData.update_candidate(candidate, %{sign_b64: sign_b64, sign_hash: sign_hash})
  end

  def unwrap_right(right, origin_identity) do
    shared_secret =
      EnigmaPq.decapsulate_secret(right.kem_ciphertext_b64, origin_identity.crypt_skey)

    unwrap_with_secret(right, shared_secret)
  end

  def unwrap_with_secret(right, shared_secret) do
    wrap_key = ReviewRightEnvelope.wrap_key(shared_secret)
    row_json = EnigmaPq.aes_gcm_decrypt(right.wrapped_row_b64, wrap_key)
    Jason.decode!(row_json)
  end

  def publish_password_row(row) do
    sign_b64 = Base.decode64!(row["sign_b64"], padding: false)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewPasswordSignHash.from_binary()
    password_b64 = row["password_b64"] && Base.decode64!(row["password_b64"], padding: false)

    changes = %{
      review_hash: row["review_hash"],
      sign_hash: sign_hash,
      origin_hash: row["origin_hash"],
      password_b64: password_b64,
      author_hash: row["author_hash"],
      deleted_flag: false,
      owner_timestamp: row["owner_timestamp"],
      sign_b64: sign_b64
    }

    changeset =
      PublicPasswordValidation.validate_origin_moderate(
        %ReviewPublicPassword{},
        changes,
        :insert
      )

    {:ok, _} = PublicPasswordData.upsert_review_public_password(changeset)
  end

  def insert_public_password(author, review, origin_hash, opts \\ []) do
    author_hash = User.extract_pq_card(author).user_hash
    password_b64 = Keyword.get_lazy(opts, :password_b64, fn -> :crypto.strong_rand_bytes(32) end)
    ts = Keyword.get(opts, :ts, System.os_time(:millisecond))

    rp = %ReviewPublicPassword{
      review_hash: review.review_hash,
      origin_hash: origin_hash,
      password_b64: password_b64,
      author_hash: author_hash,
      deleted_flag: false,
      owner_timestamp: ts
    }

    signed = sign_with_hash(rp, author.sign_skey, &ReviewPasswordSignHash.from_binary/1)

    {:ok, _} =
      %ReviewPublicPassword{}
      |> ReviewPublicPassword.create_changeset(Map.from_struct(signed))
      |> PublicPasswordData.upsert_review_public_password()

    signed
  end

  def insert_post_right(author, review, origin_hash) do
    author
    |> build_right(review, origin_hash, ReviewPostRight, &ReviewPostRightSignHash.from_binary/1)
    |> then(fn signed ->
      {:ok, _} =
        %ReviewPostRight{}
        |> ReviewPostRight.create_changeset(Map.from_struct(signed))
        |> PostRightData.upsert_post_right()

      signed
    end)
  end

  def insert_revoke_right(author, review, origin_hash) do
    author
    |> build_right(review, origin_hash, ReviewRevokeRight, &ReviewRevokeRightSignHash.from_binary/1)
    |> then(fn signed ->
      {:ok, _} =
        %ReviewRevokeRight{}
        |> ReviewRevokeRight.create_changeset(Map.from_struct(signed))
        |> RevokeRightData.upsert_revoke_right()

      signed
    end)
  end

  def sign_with_hash(struct, sign_skey, hash_fn) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> hash_fn.()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  def sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    %{struct | sign_b64: sign_b64}
  end

  def random_review_hash, do: :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()

  def random_password_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> ReviewPasswordSignHash.from_binary()

  def random_post_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> ReviewPostRightSignHash.from_binary()

  def random_revoke_sign_hash,
    do: :crypto.strong_rand_bytes(64) |> ReviewRevokeRightSignHash.from_binary()

  defp build_right(author, review, origin_hash, schema, hash_fn) do
    right =
      struct(schema, %{
        review_hash: review.review_hash,
        origin_hash: origin_hash,
        author_hash: User.extract_pq_card(author).user_hash,
        kem_ciphertext_b64: :crypto.strong_rand_bytes(32),
        wrapped_row_b64: :crypto.strong_rand_bytes(64),
        deleted_flag: false,
        owner_timestamp: System.os_time(:millisecond)
      })

    sign_with_hash(right, author.sign_skey, hash_fn)
  end
end
