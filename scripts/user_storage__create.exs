#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
user_hash = System.get_env("USER_HASH")  # Now expects "u_" prefixed string
sign_skey_hex = System.get_env("SIGN_SKEY")
uuid = System.get_env("UUID") || Ecto.UUID.generate()
value = System.get_env("VALUE") || "default_storage_value"

unless user_hash && sign_skey_hex do
  IO.puts(:stderr, """
  Error: Missing required environment variables

  Usage:
    USER_HASH=<hex> SIGN_SKEY=<hex> UUID=<uuid> VALUE="data" #{__ENV__.file}

  Example:
    # First, create a user with post_electric_user.exs and save the keys
    # Then create storage:
    USER_HASH=01abc... SIGN_SKEY=def... UUID=550e8400-e29b-41d4-a716-446655440000 VALUE="encrypted_data" #{__ENV__.file}

  Environment variables:
    USER_HASH   - User hash from the user card (string with "u_" prefix) [REQUIRED]
    SIGN_SKEY   - Signing secret key (hex string without 0x prefix) [REQUIRED]
    UUID        - UUID for this storage entry (default: auto-generated)
    VALUE       - Binary value to store (default: "default_storage_value")
    BASE_URL    - API base URL (default: http://127.0.0.1:4444)
  """)

  System.halt(1)
end

# Validate user_hash format
unless String.starts_with?(user_hash, "u_") && String.length(user_hash) == 130 do
  raise "Invalid USER_HASH format. Expected 'u_' prefix followed by 128 hex characters."
end

# Decode sign_skey
sign_skey =
  case Base.decode16(sign_skey_hex, case: :mixed) do
    {:ok, bin} -> bin
    :error -> raise "Invalid SIGN_SKEY hex string"
  end

# Encode value as binary
value_bin = :erlang.term_to_binary(value)
value_b64 = Base.encode64(value_bin, padding: false)

# Generate integrity fields
owner_timestamp = System.system_time(:second)
deleted_flag = false
parent_sign_hash = nil

# Build signature payload (simplified - in production use Chat.Data.Integrity.signature_payload)
signature_fields = %{
  "deleted_flag" => deleted_flag,
  "owner_timestamp" => owner_timestamp,
  "parent_sign_hash" => parent_sign_hash,
  "user_hash" => user_hash,
  "uuid" => uuid,
  "value_b64" => value_b64
}

signature_data =
  signature_fields
  |> Enum.sort_by(fn {key, _value} -> key end)
  |> Enum.map(fn {_key, value} ->
    cond do
      value == true -> "true"
      value == false -> "false"
      is_nil(value) -> "null"
      is_integer(value) -> Integer.to_string(value)
      is_binary(value) -> value
      true -> to_string(value)
    end
  end)
  |> Enum.join("")

sign_b64 = :crypto.sign(:mldsa87, :none, signature_data, sign_skey)

# Compute sign_hash as "uss_" + hex(SHA3-512(sign_b64))
sign_hash_binary = :crypto.hash(:sha3_512, sign_b64)
sign_hash = "uss_" <> Base.encode16(sign_hash_binary, case: :lower)

payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => user_hash,
        "uuid" => uuid,
        "value_b64" => value_b64,
        "deleted_flag" => deleted_flag,
        "parent_sign_hash" => parent_sign_hash,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => Base.encode64(sign_b64, padding: false),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{
        "relation" => "user_storage"
      }
    }
  ]
}

challenge_resp =
  Req.get!(
    base <> "/electric/v1/challenge",
    headers: [{"accept", "application/json"}]
  )

IO.puts("challenge_status=" <> to_string(challenge_resp.status))
IO.puts("challenge_body=" <> inspect(challenge_resp.body))

%{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp.body

signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
signature_b64 = Base.encode64(signature, padding: false)

payload =
  Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

resp =
  Req.post!(
    base <> "/electric/v1/ingest",
    json: payload,
    headers: [
      {"accept", "application/json"}
    ]
  )

IO.puts("ingest_status=" <> to_string(resp.status))
IO.puts("ingest_headers=" <> inspect(resp.headers))
IO.puts("ingest_body=" <> inspect(resp.body))

if resp.status == 200 do
  IO.puts("\n✓ Successfully created user_storage entry")
  IO.puts("\nStorage details:")
  IO.puts("USER_HASH=" <> user_hash)
  IO.puts("UUID=" <> uuid)
  IO.puts("SIGN_HASH=" <> sign_hash)
  IO.puts("VALUE_SIZE=" <> to_string(byte_size(value_bin)) <> " bytes")
else
  IO.puts(:stderr, "\n✗ Failed to create user_storage entry")
  System.halt(1)
end
