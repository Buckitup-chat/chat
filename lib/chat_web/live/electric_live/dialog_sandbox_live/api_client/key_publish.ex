defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.KeyPublish do
  @moduledoc """
  Publishes the sender's wrapped dialog key for a peer.
  """

  import ChatWeb.ElectricLive.SandboxHttp
  import ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Ingest, only: [sign: 2]

  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Types.DialogHash
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  def publish_dialog_key(user, peer_hash, peer_crypt_pkey, base_url) do
    dialog_hash = DialogHash.for_pair(user.user_hash, peer_hash)

    sender_msg_key =
      Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)

    {kem_wrap_key, wrapped_msg_key} = Crypto.wrap_for_peer(sender_msg_key, peer_crypt_pkey)
    owner_timestamp = TimeKeeper.now_unix()

    key_struct =
      struct(DialogKey, %{
        dialog_hash: dialog_hash,
        sender_hash: user.user_hash,
        peer_hash: peer_hash,
        peer_kem_wrap_key_b64: kem_wrap_key,
        peer_wrapped_msg_key_b64: wrapped_msg_key,
        owner_timestamp: owner_timestamp,
        deleted_flag: false
      })

    sign_b64 = sign(key_struct, user.sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "dialog_hash" => dialog_hash,
            "sender_hash" => user.user_hash,
            "peer_hash" => peer_hash,
            "peer_kem_wrap_key_b64" => encode_base64(kem_wrap_key),
            "peer_wrapped_msg_key_b64" => encode_base64(wrapped_msg_key),
            "owner_timestamp" => owner_timestamp,
            "deleted_flag" => false,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "dialog_keys"}
        }
      ]
    }

    case ingest(payload, user.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{dialog_hash: dialog_hash, log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end
end
