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
          %{name: "contact_pkey", type: "bytea", description: "ML-KEM-1024 public contact key"},
          %{name: "contact_cert", type: "bytea", description: "Contact certificate"},
          %{name: "crypt_pkey", type: "bytea", description: "ML-KEM-1024 public encryption key"},
          %{name: "crypt_cert", type: "bytea", description: "Encryption certificate"}
        ],
        example: """
        {
          "user_hash": "\\\\x013a4f2b1c...",
          "name": "Alice",
          "sign_pkey": "\\\\x9f2a1b...",
          "contact_pkey": "\\\\x8c3d4e...",
          "contact_cert": "\\\\x7b2c3a...",
          "crypt_pkey": "\\\\x4e5f6a...",
          "crypt_cert": "\\\\x9d8e7f..."
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
