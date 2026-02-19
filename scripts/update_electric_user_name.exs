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

payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => encode_hex.(user_hash)
      },
      "changes" => %{
        "name" => new_name
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
