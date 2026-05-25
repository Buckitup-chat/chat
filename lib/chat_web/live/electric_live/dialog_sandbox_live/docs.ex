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
          %{
            name: "deleted_flag",
            type: "boolean",
            description: "Signed tombstone; true = message retracted, content is empty"
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
      "dialog_message_reactions" => %{
        title: "dialog_message_reactions",
        description:
          "Encrypted emoji reactions. reaction_hash is a keyed MAC — only participants can recompute.",
        fields: [
          %{
            name: "reaction_hash",
            type: "text",
            description:
              "PK; \"dmr_\" + hex(HMAC-SHA3-512(sender_msg_key, message_id || reactor_hash || emoji))"
          },
          %{name: "dialog_hash", type: "text", description: "Dialog this reaction belongs to"},
          %{name: "message_id", type: "text", description: "Reacted-to message"},
          %{
            name: "message_sign_hash",
            type: "text",
            description: "Binds to specific message version"
          },
          %{name: "reactor_hash", type: "text", description: "Who reacted"},
          %{
            name: "type_b64",
            type: "bytea",
            description: "nonce(12) || AES-256-GCM(sender_msg_key, emoji)"
          },
          %{name: "deleted_flag", type: "boolean", description: "true = un-react"},
          %{name: "owner_timestamp", type: "integer", description: "Monotonic per reaction_hash"},
          %{name: "sign_b64", type: "bytea", description: "ML-DSA-87 signature by reactor_hash"}
        ]
      },
      "dialog_message_receipts" => %{
        title: "dialog_message_receipts",
        description:
          "Plaintext delivery/read receipts. Insert-only — receipts are irreversible facts.",
        fields: [
          %{
            name: "receipt_hash",
            type: "text",
            description:
              "PK; \"dmrc_\" + hex(SHA3-512(message_id || message_sign_hash || peer_hash || type))"
          },
          %{name: "dialog_hash", type: "text", description: "Dialog this receipt belongs to"},
          %{name: "message_id", type: "text", description: "Receipted message"},
          %{name: "peer_hash", type: "text", description: "Who generated the receipt"},
          %{
            name: "type",
            type: "string",
            description: "\"delivered\" or \"read\" — plaintext, no encryption"
          },
          %{
            name: "message_sign_hash",
            type: "text",
            description: "Binds to specific message version"
          },
          %{name: "owner_timestamp", type: "integer", description: "Monotonic per receipt_hash"},
          %{name: "sign_b64", type: "bytea", description: "ML-DSA-87 signature by peer_hash"}
        ]
      },
      "message_edit" => %{
        title: "Message Edit Flow",
        description:
          "Edit = new tip with same message_id, higher owner_timestamp, parent_sign_hash pointing to current tip's sign_hash. Sent as type=\"insert\" — server detects conflict and archives old version.",
        fields: [
          %{
            name: "message_id",
            type: "text",
            description: "Same as original message (reuse existing)"
          },
          %{
            name: "parent_sign_hash",
            type: "text",
            description: "Current tip's sign_hash (version chain link)"
          },
          %{
            name: "content_b64",
            type: "bytea",
            description: "Newly encrypted content under same sender_msg_key"
          },
          %{
            name: "refs_map_b64",
            type: "bytea",
            description: "Recomputed from current viewport tails"
          },
          %{
            name: "owner_timestamp",
            type: "integer",
            description: "Must be > current tip's owner_timestamp"
          }
        ]
      },
      "message_delete" => %{
        title: "Message Delete Flow",
        description:
          "Delete = new tip with deleted_flag: true, empty content_b64. Same chain rules as edit. No unsigned server-side delete — client sends signed tombstone.",
        fields: [
          %{name: "deleted_flag", type: "boolean", description: "Set to true for deletion"},
          %{
            name: "content_b64",
            type: "bytea",
            description: "Empty binary (no content in tombstone)"
          },
          %{
            name: "parent_sign_hash",
            type: "text",
            description: "Current tip's sign_hash"
          },
          %{
            name: "refs_map_b64",
            type: "bytea",
            description: "Recomputed from current viewport tails at deletion time"
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
