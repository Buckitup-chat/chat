defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.MessagePublish do
  @moduledoc """
  Publishes dialog messages: new, edited and deleted versions.
  """

  import ChatWeb.ElectricLive.SandboxHttp

  import ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Ingest,
    only: [sign: 2, update_payload: 3]

  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Types.DialogMessageId
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.DialogSandboxLive.Content
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  def publish_dialog_message(user, dialog_hash, plaintext, refs_tails, base_url) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        refs_tails.peer_hash
      )

    message_id = DialogMessageId.generate()
    prepared = Content.prepare_for_send(plaintext)
    content_b64 = Crypto.encrypt_content(prepared, sender_msg_key)
    refs_map_b64 = Crypto.encrypt_refs_map(refs_tails.tails, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg_struct =
      struct(DialogMessage, %{
        message_id: message_id,
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        content_b64: content_b64,
        deleted_flag: false,
        refs_map_b64: refs_map_b64,
        parent_sign_hash: nil,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(msg_struct, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "message_id" => message_id,
            "dialog_hash" => dialog_hash,
            "sender_hash" => user.user_hash,
            "content_b64" => encode_base64(content_b64),
            "deleted_flag" => false,
            "refs_map_b64" => encode_base64(refs_map_b64),
            "parent_sign_hash" => nil,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "dialog_messages"}
        }
      ]
    }

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} ->
        {:ok, %{message_id: message_id, sign_hash: sign_hash, log_entries: logs}}

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_edit_message(
        user,
        dialog_hash,
        message_id,
        current_sign_hash,
        new_plaintext,
        refs_tails,
        base_url
      ) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        refs_tails.peer_hash
      )

    prepared = Content.prepare_for_send(new_plaintext)
    content_b64 = Crypto.encrypt_content(prepared, sender_msg_key)
    refs_map_b64 = Crypto.encrypt_refs_map(refs_tails.tails, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg_struct =
      struct(DialogMessage, %{
        message_id: message_id,
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        content_b64: content_b64,
        deleted_flag: false,
        refs_map_b64: refs_map_b64,
        parent_sign_hash: current_sign_hash,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(msg_struct, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)

    payload =
      update_payload(
        "dialog_messages",
        %{
          "message_id" => message_id,
          "sender_hash" => user.user_hash,
          "dialog_hash" => dialog_hash
        },
        %{
          "content_b64" => encode_base64(content_b64),
          "deleted_flag" => false,
          "refs_map_b64" => encode_base64(refs_map_b64),
          "parent_sign_hash" => current_sign_hash,
          "owner_timestamp" => owner_timestamp,
          "sign_b64" => encode_base64(sign_b64),
          "sign_hash" => sign_hash
        }
      )

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{sign_hash: sign_hash, log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def publish_delete_message(
        user,
        dialog_hash,
        message_id,
        current_sign_hash,
        refs_tails,
        base_url
      ) do
    sender_msg_key =
      Crypto.derive_sender_msg_key(
        user.sign_skey,
        user.crypt_skey,
        user.contact_skey,
        refs_tails.peer_hash
      )

    refs_map_b64 = Crypto.encrypt_refs_map(refs_tails.tails, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg_struct =
      struct(DialogMessage, %{
        message_id: message_id,
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        content_b64: "",
        deleted_flag: true,
        refs_map_b64: refs_map_b64,
        parent_sign_hash: current_sign_hash,
        owner_timestamp: owner_timestamp
      })

    sign_b64 = sign(msg_struct, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)

    payload =
      update_payload(
        "dialog_messages",
        %{
          "message_id" => message_id,
          "sender_hash" => user.user_hash,
          "dialog_hash" => dialog_hash
        },
        %{
          "content_b64" => "",
          "deleted_flag" => true,
          "refs_map_b64" => encode_base64(refs_map_b64),
          "parent_sign_hash" => current_sign_hash,
          "owner_timestamp" => owner_timestamp,
          "sign_b64" => encode_base64(sign_b64),
          "sign_hash" => sign_hash
        }
      )

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end
end
