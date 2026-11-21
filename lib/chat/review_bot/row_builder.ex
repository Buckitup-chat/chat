defmodule Chat.ReviewBot.RowBuilder do
  @moduledoc "Builds signed PQ row structs and ingest mutations for review bot ingest. No writes."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.Types.ReviewWriteTokenSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User
  alias Chat.ReviewBot.Identity
  alias Chat.ReviewBot.Worker
  alias Chat.TimeKeeper
  alias EnigmaPq

  def generate_identity(origin_name) do
    User.generate_pq_identity("ReviewBot_#{origin_name}")
  end

  def origin_bot(bot_hash, bot_identity, origin_hash, origin_crypt_pkey, origin_sign_skey) do
    {secret, encrypted} = Identity.wrap(bot_identity, origin_crypt_pkey)

    %OriginBot{
      bot_hash: bot_hash,
      origin_hash: origin_hash,
      secret_b64: secret,
      encrypted_identity_b64: encrypted,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }
    |> sign_struct(origin_sign_skey, &OriginBotSignHash.from_binary/1)
  end

  def origin_vouch(origin_hash, origin_sign_skey, bot_hash) do
    "origins.#{origin_hash}.reviews.write"
    |> build_vouch(origin_hash, bot_hash, origin_sign_skey)
  end

  @device_vouch_shapes [
    :review_write_token,
    :review,
    :review_password_candidate,
    :review_post_right_candidate,
    :review_revoke_right_candidate,
    :review_list,
    :review_public_passwords
  ]

  def device_vouches(owner_hash, owner_sign_skey, bot_hash, device_sn) do
    Enum.map(@device_vouch_shapes, fn shape ->
      "device.#{device_sn}.storage.write.#{shape}"
      |> build_vouch(owner_hash, bot_hash, owner_sign_skey)
    end)
  end

  @doc """
  Signs `token` and returns the review_write_tokens insert mutation. `sign` defaults
  to the token's running bot; pass it when already inside that bot's `Worker`.
  """
  def review_write_token_mutation(%ReviewWriteToken{} = token, sign \\ nil) do
    {sign_b64, sign_hash} = sign_token(token, sign)

    %{
      "type" => "insert",
      "modified" => %{
        "nonce_hash" => token.nonce_hash,
        "nonce_enc_b64" => token.nonce_enc_b64,
        "origin_hash" => token.origin_hash,
        "review_bot_hash" => token.review_bot_hash,
        "origin_order_hash" => token.origin_order_hash,
        "parent_nonce_hash" => token.parent_nonce_hash,
        "user_hash" => token.user_hash,
        "review_hash" => token.review_hash,
        "deleted_flag" => token.deleted_flag,
        "owner_timestamp" => token.owner_timestamp,
        "sign_b64" => sign_b64,
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review_write_tokens"}
    }
  end

  @doc "Like `review_write_token_mutation/2`, but an update mutation carrying `fields`."
  def review_write_token_update_mutation(%ReviewWriteToken{} = token, fields, sign \\ nil) do
    {sign_b64, sign_hash} = sign_token(token, sign)

    changes =
      token
      |> Map.take([:owner_timestamp | fields])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.merge(%{"sign_b64" => sign_b64, "sign_hash" => sign_hash})

    %{
      "type" => "update",
      "original" => %{"nonce_hash" => token.nonce_hash},
      "changes" => changes,
      "syncMetadata" => %{"relation" => "review_write_tokens"}
    }
  end

  defp sign_token(%ReviewWriteToken{review_bot_hash: bot_hash} = token, sign) do
    sign = sign || (&Worker.sign(bot_hash, &1))
    sign_b64 = token |> Integrity.signature_payload() |> sign.()
    {sign_b64, sign_b64 |> EnigmaPq.hash() |> ReviewWriteTokenSignHash.from_binary()}
  end

  def derive_hash(sign_pkey) do
    sign_pkey
    |> EnigmaPq.hash()
    |> UserHash.from_binary()
  end

  defp build_vouch(kind, issuer_hash, subject_hash, sign_skey) do
    vt = %VouchToken{
      kind: kind,
      issuer_hash: issuer_hash,
      subject_hash: subject_hash,
      owner_timestamp: TimeKeeper.now_unix(),
      deleted_flag: false
    }

    sign_b64 =
      vt
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    %{vt | sign_b64: sign_b64}
  end

  defp sign_struct(struct, sign_skey, hash_fn) do
    sign_b64 =
      struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    sign_hash = sign_b64 |> EnigmaPq.hash() |> hash_fn.()
    %{struct | sign_b64: sign_b64, sign_hash: sign_hash}
  end
end
