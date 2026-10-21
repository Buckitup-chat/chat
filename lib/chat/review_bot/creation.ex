defmodule Chat.ReviewBot.Creation do
  @moduledoc "Pure mutation builders for review bot creation. No side effects."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User
  alias Chat.ReviewBot.Identity
  alias Chat.TimeKeeper
  alias EnigmaPq

  def new_bot(origin_name) do
    User.generate_pq_identity("ReviewBot_#{origin_name}")
  end

  def card(bot_identity) do
    User.extract_pq_card(bot_identity)
  end

  def origin_bot(bot_card, bot_identity, origin_hash, origin_crypt_pkey, origin_sign_skey) do
    {secret, encrypted} = Identity.wrap(bot_identity, origin_crypt_pkey)

    bot = %OriginBot{
      bot_hash: bot_card.user_hash,
      origin_hash: origin_hash,
      secret_b64: secret,
      encrypted_identity_b64: encrypted,
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    sign_struct(bot, origin_sign_skey, &OriginBotSignHash.from_binary/1)
  end

  def origin_vouch(origin_hash, origin_sign_skey, bot_card) do
    kind = "origins.#{origin_hash}.reviews.write"
    build_vouch(kind, origin_hash, bot_card.user_hash, origin_sign_skey)
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

  def device_vouches(owner_identity, bot_hash, device_sn) do
    owner_card = User.extract_pq_card(owner_identity)

    @device_vouch_shapes
    |> Enum.map(fn shape ->
      kind = "device.#{device_sn}.storage.write.#{shape}"
      build_vouch(kind, owner_card.user_hash, bot_hash, owner_identity.sign_skey)
    end)
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

  def bot_hash(%{sign_pkey: sign_pkey}) do
    sign_pkey
    |> EnigmaPq.hash()
    |> UserHash.from_binary()
  end
end
