defmodule Chat.Test.ElectricIngestFixtures do
  @moduledoc "Signed rows and ingest payloads shared by Electric ingest controller tests."

  import Chat.Test.ElectricIngestHelpers, only: [signature_of: 2, to_base64: 1]

  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageSignHash

  @doc "Ingest payload with a single `user_cards` insert of `modified`."
  def user_card_payload(modified) do
    %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => modified,
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }
  end

  @doc "The `modified` map of a `user_cards` mutation for a signed card."
  def user_card_modified(card) do
    %{
      "user_hash" => card.user_hash,
      "sign_pkey" => to_base64(card.sign_pkey),
      "contact_pkey" => to_base64(card.contact_pkey),
      "contact_cert" => to_base64(card.contact_cert),
      "crypt_pkey" => to_base64(card.crypt_pkey),
      "crypt_cert" => to_base64(card.crypt_cert),
      "name" => card.name,
      "deleted_flag" => card.deleted_flag,
      "owner_timestamp" => card.owner_timestamp,
      "sign_b64" => to_base64(card.sign_b64)
    }
  end

  @doc """
  `DialogMessage` signed by `identity`, with random content and refs.
  `attrs` override `:message_id`, `:content_b64`, `:deleted_flag`, `:refs_map_b64`,
  `:parent_sign_hash` and `:owner_timestamp`.
  """
  def signed_message(identity, dialog_hash, sender_hash, attrs \\ []) do
    msg = %DialogMessage{
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      content_b64: Keyword.get(attrs, :content_b64, :crypto.strong_rand_bytes(32)),
      deleted_flag: Keyword.get(attrs, :deleted_flag, false),
      refs_map_b64: Keyword.get(attrs, :refs_map_b64, :crypto.strong_rand_bytes(24)),
      parent_sign_hash: Keyword.get(attrs, :parent_sign_hash, nil),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, System.os_time(:millisecond))
    }

    sign_b64 = signature_of(msg, identity.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> DialogMessageSignHash.from_binary()
    %{msg | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  @doc "`DialogKey` from `sender_hash` to `peer_hash`, signed by `identity`, with random wrapped keys."
  def signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash) do
    dk = %DialogKey{
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      peer_hash: peer_hash,
      peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
      peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }

    %{dk | sign_b64: signature_of(dk, identity.sign_skey)}
  end
end
