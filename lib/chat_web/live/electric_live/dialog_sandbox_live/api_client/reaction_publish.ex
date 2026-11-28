defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.ReactionPublish do
  @moduledoc """
  Publishes message reactions (add / delete) and read receipts.
  """

  import ChatWeb.ElectricLive.SandboxHttp

  import ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Ingest,
    only: [publish_insert: 4, sign: 2, update_payload: 3]

  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  def publish_reaction(
        user,
        dialog_hash,
        message_id,
        message_sign_hash,
        emoji,
        peer_hash,
        base_url
      ) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    reaction_hash =
      Crypto.compute_reaction_hash(sender_msg_key, message_id, user.user_hash, emoji)

    type_b64 = Crypto.encrypt_emoji(emoji, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    reaction_struct =
      struct(DialogMessageReaction, %{
        reaction_hash: reaction_hash,
        dialog_hash: dialog_hash,
        message_id: message_id,
        message_sign_hash: message_sign_hash,
        reactor_hash: user.user_hash,
        type_b64: type_b64,
        deleted_flag: false,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(reaction_struct, user.sign_skey)

    fields = %{
      "reaction_hash" => reaction_hash,
      "dialog_hash" => dialog_hash,
      "message_id" => message_id,
      "message_sign_hash" => message_sign_hash,
      "reactor_hash" => user.user_hash,
      "type_b64" => encode_base64(type_b64),
      "deleted_flag" => false,
      "owner_timestamp" => owner_timestamp,
      "sign_b64" => encode_base64(sign_b64)
    }

    publish_insert("dialog_message_reactions", fields, user.sign_skey, base_url)
  end

  def delete_reaction(user, existing_reaction, peer_hash, base_url) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    type_b64 = Crypto.encrypt_emoji("", sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    reaction_struct =
      struct(DialogMessageReaction, %{
        reaction_hash: existing_reaction.reaction_hash,
        dialog_hash: existing_reaction.dialog_hash,
        message_id: existing_reaction.message_id,
        message_sign_hash: existing_reaction.message_sign_hash,
        reactor_hash: user.user_hash,
        type_b64: type_b64,
        deleted_flag: true,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(reaction_struct, user.sign_skey)

    payload =
      update_payload(
        "dialog_message_reactions",
        %{
          "reaction_hash" => existing_reaction.reaction_hash,
          "reactor_hash" => user.user_hash,
          "dialog_hash" => existing_reaction.dialog_hash,
          "message_id" => existing_reaction.message_id
        },
        %{
          "type_b64" => encode_base64(type_b64),
          "deleted_flag" => true,
          "owner_timestamp" => owner_timestamp,
          "sign_b64" => encode_base64(sign_b64)
        }
      )

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_receipt(user, dialog_hash, message_id, message_sign_hash, type, base_url) do
    receipt_hash =
      Crypto.compute_receipt_hash(message_id, message_sign_hash, user.user_hash, type)

    owner_timestamp = TimeKeeper.now_unix()

    receipt_struct =
      struct(DialogMessageReceipt, %{
        receipt_hash: receipt_hash,
        dialog_hash: dialog_hash,
        message_id: message_id,
        peer_hash: user.user_hash,
        type: type,
        message_sign_hash: message_sign_hash,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(receipt_struct, user.sign_skey)

    fields = %{
      "receipt_hash" => receipt_hash,
      "dialog_hash" => dialog_hash,
      "message_id" => message_id,
      "peer_hash" => user.user_hash,
      "type" => type,
      "message_sign_hash" => message_sign_hash,
      "owner_timestamp" => owner_timestamp,
      "sign_b64" => encode_base64(sign_b64)
    }

    publish_insert("dialog_message_receipts", fields, user.sign_skey, base_url)
  end
end
