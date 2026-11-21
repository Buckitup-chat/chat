defmodule Chat.Test.ReviewGateFixtures do
  @moduledoc false

  import Chat.Test.ReviewFixtures, only: [sign_with_hash: 3, sign_with_key: 2]

  alias Chat.Data.Review.Validation
  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.Repo
  alias Chat.ReviewBot.Identity
  alias Phoenix.Sync.Writer.Operation

  def check_insert(author_hash, origin_hash, pop_context \\ %{}) do
    %Operation{
      operation: :insert,
      changes: %{"author_hash" => author_hash, "origin_hash" => origin_hash}
    }
    |> Validation.check_review_gate(pop_context)
  end

  def set_review_access(origin_hash, value) do
    Repo.insert!(%OriginSetting{
      origin_hash: origin_hash,
      key: "review_access",
      value: value,
      deleted_flag: false,
      owner_timestamp: 1,
      sign_b64: <<0::256>>
    })
  end

  def insert_origin_vouch(issuer_identity, origin_hash, subject_hash, scope_suffix, opts \\ []) do
    insert_vouch(
      issuer_identity,
      User.extract_pq_card(issuer_identity).user_hash,
      subject_hash,
      "origins.#{origin_hash}.#{scope_suffix}",
      opts
    )
  end

  def insert_vouch(issuer_identity, issuer_hash, subject_hash, kind, opts \\ []) do
    vt =
      %VouchToken{
        kind: kind,
        issuer_hash: issuer_hash,
        subject_hash: subject_hash,
        owner_timestamp: Keyword.get(opts, :ts, System.os_time(:millisecond)),
        deleted_flag: Keyword.get(opts, :deleted_flag, false)
      }
      |> sign_with_key(issuer_identity.sign_skey)

    {:ok, _} =
      VouchTokenData.upsert_vouch_token(
        VouchToken.create_changeset(%VouchToken{}, Map.from_struct(vt))
      )
  end

  @doc "Exact bind vouch `origins.<oh>.reviews.write.<nonce_hash>` from the bot to the user."
  def insert_bind_vouch(bot_identity, origin_hash, user_hash, nonce, opts \\ []) do
    insert_vouch(
      bot_identity,
      User.extract_pq_card(bot_identity).user_hash,
      user_hash,
      "origins.#{origin_hash}.reviews.write.#{ReviewWriteTokenNonceHash.from_nonce(nonce)}",
      opts
    )
  end

  def insert_bound_token(bot_identity, origin_hash, user_hash, opts \\ []) do
    nonce = "tok_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    bot_hash = User.extract_pq_card(bot_identity).user_hash

    token =
      %ReviewWriteToken{
        nonce_hash: ReviewWriteTokenNonceHash.from_nonce(nonce),
        nonce_enc_b64: Identity.wrap_nonce(nonce, bot_identity.crypt_skey),
        origin_hash: origin_hash,
        review_bot_hash: bot_hash,
        user_hash: user_hash,
        review_hash: Keyword.get(opts, :review_hash),
        deleted_flag: Keyword.get(opts, :deleted_flag, false),
        owner_timestamp: System.os_time(:millisecond)
      }
      |> sign_with_hash(bot_identity.sign_skey, &ReviewWriteTokenSignHash.from_binary/1)

    {:ok, _} =
      TokenData.upsert_review_write_token(
        ReviewWriteToken.create_changeset(%ReviewWriteToken{}, Map.from_struct(token))
      )

    nonce
  end
end
