defmodule ChatWeb.ElectricLive.UserSandboxLive.Docs do
  @moduledoc """
  Static documentation content for the Electric API Sandbox.
  """

  def get_docs do
    %{
      "user_card" => %{
        title: "User Card",
        description: "Represents a user identity with Post-Quantum public keys",
        fields: [
          %{
            name: "user_hash",
            type: "bytea",
            description: "SHA3-512 hash of sign_pkey with 0x01 prefix (primary key, 65 bytes)"
          },
          %{name: "name", type: "text", description: "User display name"},
          %{name: "sign_pkey", type: "bytea", description: "ML-DSA-87 public signing key"},
          %{name: "contact_pkey", type: "bytea", description: "ECC secp256k1 public contact key"},
          %{name: "contact_cert", type: "bytea", description: "Contact certificate (sign_pkey signature of contact_pkey)"},
          %{name: "crypt_pkey", type: "bytea", description: "ML-KEM-1024 public encryption key"},
          %{name: "crypt_cert", type: "bytea", description: "Encryption certificate (sign_pkey signature of crypt_pkey)"},
          %{name: "deleted_flag", type: "boolean", description: "Soft delete flag for conflict resolution"},
          %{name: "owner_timestamp", type: "bigint", description: "Owner's timestamp for conflict resolution (latest wins)"},
          %{name: "sign_b64", type: "bytea", description: "Signature of all other fields for data integrity verification"}
        ],
        example: """
        {
          "user_hash": "\\\\x013a4f2b1c...",
          "name": "Alice",
          "sign_pkey": "n5Khu7...",
          "contact_pkey": "jD1O5a...",
          "contact_cert": "eyxDqm...",
          "crypt_pkey": "Tl9mpQ...",
          "crypt_cert": "nY5/8w...",
          "deleted_flag": false,
          "owner_timestamp": 1710000000000,
          "sign_b64": "GisxPT..."
        }
        """
      },
      "user_storage" => %{
        title: "User Storage",
        description: "Key-value storage entries owned by a user (max 10MB per entry)",
        fields: [
          %{
            name: "user_hash",
            type: "bytea",
            description: "Foreign key to user_card.user_hash (part of composite primary key)"
          },
          %{
            name: "uuid",
            type: "uuid",
            description: "Storage entry identifier (part of composite primary key)"
          },
          %{name: "value", type: "bytea", description: "Binary value (max 10MB)"}
        ],
        example: """
        {
          "user_hash": "\\\\x013a4f2b1c...",
          "uuid": "550e8400-e29b-41d4-a716-446655440000",
          "value": "\\\\x54657374206461746120696e2062696e617279"
        }
        """
      }
    }
  end
end
