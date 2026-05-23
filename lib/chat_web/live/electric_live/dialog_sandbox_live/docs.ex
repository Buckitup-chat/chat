defmodule ChatWeb.ElectricLive.DialogSandboxLive.Docs do
  @moduledoc """
  Static documentation content for the Dialog Sandbox sidebar.
  """

  def get_docs do
    %{
      "dialog_keys" => %{
        title: "dialog_keys",
        description:
          "Wrapped sender_msg_key published by one author for one dialog. Two rows per dialog (one per direction).",
        fields: [
          %{
            name: "dialog_hash",
            type: "text",
            description: "PK part; \"di_\" + hex(SHA3-512(sorted hashes))"
          },
          %{name: "sender_hash", type: "text", description: "PK part; author of this msg key"},
          %{name: "peer_hash", type: "text", description: "The other participant"},
          %{
            name: "peer_kem_wrap_key_b64",
            type: "bytea",
            description: "ML-KEM-1024 ciphertext to peer's crypt_pkey"
          },
          %{
            name: "peer_wrapped_msg_key_b64",
            type: "bytea",
            description: "nonce(12) || AES-256-GCM(wrap_key, sender_msg_key)"
          },
          %{
            name: "owner_timestamp",
            type: "integer",
            description: "Monotonic; must increase on updates"
          },
          %{name: "deleted_flag", type: "boolean", description: "true = author blocked peer"},
          %{name: "sign_b64", type: "bytea", description: "ML-DSA-87 signature by sender_hash"}
        ]
      },
      "dialog_messages" => %{
        title: "dialog_messages",
        description:
          "Current tip of each message's version chain. Content encrypted under sender_msg_key.",
        fields: [
          %{name: "message_id", type: "text", description: "PK; \"dmsg_\" + UUIDv7"},
          %{name: "dialog_hash", type: "text", description: "Dialog this message belongs to"},
          %{name: "sender_hash", type: "text", description: "Author"},
          %{
            name: "content_b64",
            type: "bytea",
            description: "nonce(12) || AES-256-GCM ciphertext"
          },
          %{name: "refs_map_b64", type: "bytea", description: "Encrypted DAG tail references"},
          %{
            name: "parent_sign_hash",
            type: "text",
            description: "FK to prior version; NULL for first"
          },
          %{name: "owner_timestamp", type: "integer", description: "Monotonic per message_id"},
          %{name: "sign_b64", type: "bytea", description: "ML-DSA-87 signature by sender_hash"},
          %{name: "sign_hash", type: "text", description: "\"dms_\" + hex(SHA3-512(sign_b64))"}
        ]
      },
      "key_derivation" => %{
        title: "Key Derivation",
        description:
          "HKDF-SHA3-256 derivation of sender_msg_key from private keys + peer identity.",
        fields: [
          %{
            name: "IKM",
            type: "binary",
            description: "sign_skey || crypt_skey || contact_skey || peer_user_hash"
          },
          %{name: "salt", type: "string", description: "\"buckitup/dialog-mk/v1\""},
          %{name: "info", type: "string", description: "\"dialog-mk\""},
          %{
            name: "output",
            type: "32 bytes",
            description: "AES-256-GCM key for all messages in this direction"
          }
        ]
      },
      "key_wrapping" => %{
        title: "Key Wrapping",
        description: "KEM-encapsulate sender_msg_key so the peer can decrypt messages.",
        fields: [
          %{
            name: "step 1",
            type: "KEM",
            description: "ML-KEM-1024.Encap(peer.crypt_pkey) → shared_secret + kem_ct"
          },
          %{
            name: "step 2",
            type: "KDF",
            description: "HKDF(shared_secret, salt=\"buckitup/dialog-wrap/v1\", info=\"wrap\")"
          },
          %{
            name: "step 3",
            type: "wrap",
            description: "AES-256-GCM.encrypt(wrap_key, sender_msg_key)"
          }
        ]
      }
    }
  end
end
