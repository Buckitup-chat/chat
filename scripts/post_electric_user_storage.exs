#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
user_hash_hex = System.get_env("USER_HASH")
sign_skey_hex = System.get_env("SIGN_SKEY")
uuid = System.get_env("UUID") || Ecto.UUID.generate()
value = System.get_env("VALUE") || "default_storage_value"

encode_hex = fn bin -> "\\x" <> Base.encode16(bin, case: :lower) end

unless user_hash_hex && sign_skey_hex do
  IO.puts(:stderr, """
  Error: Missing required environment variables

  Usage:
    USER_HASH=<hex> SIGN_SKEY=<hex> UUID=<uuid> VALUE="data" #{__ENV__.file}

  Example:
    # First, create a user with post_electric_user.exs and save the keys
    # Then create storage:
    USER_HASH=01abc... SIGN_SKEY=def... UUID=550e8400-e29b-41d4-a716-446655440000 VALUE="encrypted_data" #{__ENV__.file}

  Environment variables:
    USER_HASH   - User hash from the user card (hex string without 0x prefix) [REQUIRED]
    SIGN_SKEY   - Signing secret key (hex string without 0x prefix) [REQUIRED]
    UUID        - UUID for this storage entry (default: auto-generated)
    VALUE       - Binary value to store (default: "default_storage_value")
    BASE_URL    - API base URL (default: http://127.0.0.1:4444)
  """)

  System.halt(1)
end

# Decode the hex strings
user_hash =
  case Base.decode16(user_hash_hex, case: :mixed) do
    {:ok, bin} -> bin
    :error -> raise "Invalid USER_HASH hex string"
  end

sign_skey =
  case Base.decode16(sign_skey_hex, case: :mixed) do
    {:ok, bin} -> bin
    :error -> raise "Invalid SIGN_SKEY hex string"
  end

# Encode value as binary
value_bin = :erlang.term_to_binary(value)

payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => encode_hex.(user_hash),
        "uuid" => uuid,
        "value" => encode_hex.(value_bin)
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
  IO.puts("USER_HASH=" <> user_hash_hex)
  IO.puts("UUID=" <> uuid)
  IO.puts("VALUE_SIZE=" <> to_string(byte_size(value_bin)) <> " bytes")
else
  IO.puts(:stderr, "\n✗ Failed to create user_storage entry")
  System.halt(1)
end
