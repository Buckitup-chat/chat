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
            type: "text",
            description: "SHA3-512 hash of sign_pkey as URL-friendly hex string (primary key, format: \"u_\" + 128 hex chars = 130 chars total)"
          },
          %{name: "name", type: "text", description: "User display name"},
          %{name: "sign_pkey", type: "text", description: "Base64-encoded ML-DSA-87 public signing key"},
          %{name: "contact_pkey", type: "text", description: "Base64-encoded ECC secp256k1 public contact key"},
          %{name: "contact_cert", type: "text", description: "Base64-encoded contact certificate (sign_pkey signature of contact_pkey)"},
          %{name: "crypt_pkey", type: "text", description: "Base64-encoded ML-KEM-1024 public encryption key"},
          %{name: "crypt_cert", type: "text", description: "Base64-encoded encryption certificate (sign_pkey signature of crypt_pkey)"},
          %{name: "deleted_flag", type: "boolean", description: "Soft delete flag for conflict resolution"},
          %{name: "owner_timestamp", type: "bigint", description: "Owner's timestamp for conflict resolution (latest wins)"},
          %{name: "sign_b64", type: "bytea", description: "Signature of all other fields for data integrity verification"}
        ],
        example: """
        {
          "user_hash": "u_3a4f2b1c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e",
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
            type: "text",
            description: "Foreign key to user_card.user_hash (part of composite primary key, format: \"u_\" + 128 hex chars)"
          },
          %{
            name: "uuid",
            type: "uuid",
            description: "Storage entry identifier (part of composite primary key)"
          },
          %{name: "value_b64", type: "text", description: "Base64-encoded binary value (max 10MB)"},
          %{
            name: "sign_hash",
            type: "text",
            description: "Signature hash (format: \"uss_\" + 128 hex chars = 132 chars total)"
          },
          %{
            name: "parent_sign_hash",
            type: "text",
            description: "Parent version's signature hash (format: \"uss_\" + 128 hex chars, nullable)"
          },
          %{name: "owner_timestamp", type: "bigint", description: "Monotonic timestamp for conflict resolution"},
          %{name: "sign_b64", type: "text", description: "Base64-encoded ML-DSA-87 signature for integrity verification"},
          %{name: "deleted_flag", type: "boolean", description: "Soft delete flag"}
        ],
        example: """
        {
          "user_hash": "u_3a4f2b1c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e",
          "uuid": "550e8400-e29b-41d4-a716-446655440000",
          "value_b64": "VGVzdCBkYXRhIGluIGJpbmFyeQ==",
          "sign_hash": "uss_9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a0854657374206461746120696e2062696e6172799f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
          "parent_sign_hash": null,
          "owner_timestamp": 1710000000000,
          "sign_b64": "GisxPT...",
          "deleted_flag": false
        }
        """
      }
    }
  end
end
