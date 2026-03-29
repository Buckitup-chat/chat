#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
user_hash = System.get_env("USER_HASH")  # Now expects "u_" prefixed string
sign_skey_hex = System.get_env("SIGN_SKEY")
uuid = System.get_env("UUID")
new_value = System.get_env("NEW_VALUE") || "updated_storage_value"

unless user_hash && sign_skey_hex && uuid do
  IO.puts(:stderr, """
  Error: Missing required environment variables

  Usage:
    USER_HASH=<hex> SIGN_SKEY=<hex> UUID=<uuid> NEW_VALUE="data" #{__ENV__.file}

  Example:
    # First, create a user storage entry with post_electric_user_storage.exs
    # Then update the value:
    USER_HASH=01abc... SIGN_SKEY=def... UUID=550e8400-e29b-41d4-a716-446655440000 NEW_VALUE="new_encrypted_data" #{__ENV__.file}

  Environment variables:
    USER_HASH   - User hash from the user card (string with "u_" prefix) [REQUIRED]
    SIGN_SKEY   - Signing secret key (hex string without 0x prefix) [REQUIRED]
    UUID        - UUID of the storage entry to update [REQUIRED]
    NEW_VALUE   - New binary value to store (default: "updated_storage_value")
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

# Encode new value as binary
new_value_bin = :erlang.term_to_binary(new_value)
value_b64 = Base.encode64(new_value_bin, padding: false)

# Fetch existing storage to get parent_sign_hash and current timestamp
get_resp =
  Req.get!(
    base <> "/electric/v1/shape/user_storage?where=user_hash='#{user_hash}' AND uuid='#{uuid}'",
    headers: [{"accept", "application/json"}]
  )

current_storage =
  case get_resp.body do
    [storage | _] -> storage
    _ -> raise "Storage entry not found"
  end

current_timestamp = Map.get(current_storage, "owner_timestamp", 0)
owner_timestamp = current_timestamp + 1
parent_sign_hash = Map.get(current_storage, "sign_hash")
deleted_flag = false

# Build signature payload
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

# Compute sign_hash
sign_hash_binary = :crypto.hash(:sha3_512, sign_b64)
sign_hash = "uss_" <> Base.encode16(sign_hash_binary, case: :lower)

payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => user_hash,
        "uuid" => uuid
      },
      "changes" => %{
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
  IO.puts("\n✓ Successfully updated user_storage entry")
  IO.puts("\nStorage details:")
  IO.puts("USER_HASH=" <> user_hash)
  IO.puts("UUID=" <> uuid)
  IO.puts("SIGN_HASH=" <> sign_hash)
  IO.puts("NEW_VALUE_SIZE=" <> to_string(byte_size(new_value_bin)) <> " bytes")
else
  IO.puts(:stderr, "\n✗ Failed to update user_storage entry")
  System.halt(1)
end
