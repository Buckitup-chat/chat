#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
new_name = System.get_env("NEW_NAME") || "Updated Name"
user_hash_hex = System.get_env("USER_HASH")
sign_skey_hex = System.get_env("SIGN_SKEY")

encode_hex = fn bin -> "\\x" <> Base.encode16(bin, case: :lower) end

unless user_hash_hex && sign_skey_hex do
  IO.puts(:stderr, """
  Error: Missing required environment variables

  Usage:
    USER_HASH=<hex> SIGN_SKEY=<hex> NEW_NAME="New Name" #{__ENV__.file}

  Example:
    # First, create a user with post_electric_user.exs and save the keys
    # Then update the name:
    USER_HASH=01abc... SIGN_SKEY=def... NEW_NAME="Alice Updated" #{__ENV__.file}

  Environment variables:
    USER_HASH   - User hash from the user card (hex string without 0x prefix)
    SIGN_SKEY   - Signing secret key (hex string without 0x prefix)
    NEW_NAME    - New name for the user (default: "Updated Name")
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

# Get current user card to retrieve sign_pkey and current timestamp
get_resp =
  Req.get!(
    base <> "/electric/v1/shape/user_card?where=user_hash='#{encode_hex.(user_hash)}'",
    headers: [{"accept", "application/json"}]
  )

IO.puts("get_status=" <> to_string(get_resp.status))

current_card =
  case get_resp.body do
    [card | _] -> card
    _ -> raise "User card not found"
  end

current_timestamp = Map.get(current_card, "owner_timestamp", 0)
new_timestamp = current_timestamp + 1

# Retrieve sign_pkey from current card
sign_pkey_hex = String.replace_prefix(current_card["sign_pkey"], "\\x", "")
{:ok, sign_pkey} = Base.decode16(sign_pkey_hex, case: :mixed)

# Create signature payload for the update
signature_payload = %{
  user_hash: user_hash,
  sign_pkey: sign_pkey,
  contact_pkey: Base.decode16!(String.replace_prefix(current_card["contact_pkey"], "\\x", ""), case: :mixed),
  contact_cert: Base.decode16!(String.replace_prefix(current_card["contact_cert"], "\\x", ""), case: :mixed),
  crypt_pkey: Base.decode16!(String.replace_prefix(current_card["crypt_pkey"], "\\x", ""), case: :mixed),
  crypt_cert: Base.decode16!(String.replace_prefix(current_card["crypt_cert"], "\\x", ""), case: :mixed),
  name: new_name,
  deleted_flag: Map.get(current_card, "deleted_flag", false),
  owner_timestamp: new_timestamp
}

signature_data = :erlang.term_to_binary(signature_payload)
sign_b64 = :crypto.sign(:mldsa87, :none, signature_data, sign_skey)

payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => encode_hex.(user_hash)
      },
      "changes" => %{
        "name" => new_name,
        "owner_timestamp" => new_timestamp,
        "sign_b64" => encode_hex.(sign_b64)
      },
      "syncMetadata" => %{
        "relation" => "user_cards"
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
  IO.puts("\n✓ Successfully updated user name to: #{new_name}")
else
  IO.puts(:stderr, "\n✗ Failed to update user name")
  System.halt(1)
end
