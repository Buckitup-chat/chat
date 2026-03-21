#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"

encode_hex = fn bin -> "\\x" <> Base.encode16(bin, case: :lower) end
encode_b64 = fn bin -> Base.encode64(bin, padding: false) end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("USER CARD SCENARIO: CREATE → GET → UPDATE → DELETE")
IO.puts(String.duplicate("=", 80))

# ============================================================================
# STEP 1: CREATE USER
# ============================================================================
IO.puts("\n[1/4] Creating user card...")

name = "Test User #{:rand.uniform(1000)}"

{sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
{crypt_pkey, _crypt_skey} = :crypto.generate_key(:mlkem1024, [])
{contact_pkey, _contact_skey} = :crypto.generate_key(:mldsa44, [])

user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)

crypt_cert = :crypto.sign(:mldsa87, :none, crypt_pkey, sign_skey)
contact_cert = :crypto.sign(:mldsa87, :none, contact_pkey, sign_skey)

owner_timestamp = 0
deleted_flag = false

signature_fields = %{
  "contact_cert" => contact_cert,
  "contact_pkey" => contact_pkey,
  "crypt_cert" => crypt_cert,
  "crypt_pkey" => crypt_pkey,
  "deleted_flag" => deleted_flag,
  "name" => name,
  "owner_timestamp" => owner_timestamp,
  "sign_pkey" => sign_pkey,
  "user_hash" => user_hash
}

encode_field = fn {key, value} ->
  cond do
    String.ends_with?(key, "_b64") -> Base.encode64(value)
    String.ends_with?(key, "_cert") -> Base.encode64(value)
    String.ends_with?(key, "_pkey") -> Base.encode64(value)
    String.ends_with?(key, "_hash") -> Base.encode16(value, case: :lower)
    value == true -> "true"
    value == false -> "false"
    is_nil(value) -> "null"
    is_integer(value) -> Integer.to_string(value)
    is_binary(value) -> value
    true -> to_string(value)
  end
end

signature_data =
  signature_fields
  |> Enum.sort_by(fn {key, _value} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

sign_b64 = :crypto.sign(:mldsa87, :none, signature_data, sign_skey)

payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => encode_hex.(user_hash),
        "sign_pkey" => encode_b64.(sign_pkey),
        "contact_pkey" => encode_b64.(contact_pkey),
        "contact_cert" => encode_b64.(contact_cert),
        "crypt_pkey" => encode_b64.(crypt_pkey),
        "crypt_cert" => encode_b64.(crypt_cert),
        "name" => name,
        "deleted_flag" => deleted_flag,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => encode_b64.(sign_b64)
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

%{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp.body

signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
signature_b64 = Base.encode64(signature, padding: false)

payload =
  Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

create_resp =
  Req.post!(
    base <> "/electric/v1/ingest",
    json: payload,
    headers: [{"accept", "application/json"}]
  )

if create_resp.status != 200 do
  IO.puts(:stderr, "✗ Failed to create user: #{inspect(create_resp.body)}")
  System.halt(1)
end

user_hash_hex = Base.encode16(user_hash, case: :lower)
IO.puts("✓ Created user: #{name}")
IO.puts("  User hash: #{user_hash_hex}")

# Wait for propagation through Phoenix.Sync
Process.sleep(5000)

# ============================================================================
# STEP 2: GET USER
# ============================================================================
IO.puts("\n[2/4] Retrieving user card...")

# Step 1: Get handle and offset
resp1 =
  Req.get!(
    base <> "/electric/v1/user_card",
    params: %{offset: "-1"},
    headers: [{"accept", "application/json"}]
  )

handle = List.first(Req.Response.get_header(resp1, "electric-handle"))
offset = List.first(Req.Response.get_header(resp1, "electric-offset"))

if is_nil(handle) or is_nil(offset) do
  raise "Missing electric-handle/electric-offset headers"
end

# Step 2: Fetch actual data
get_resp =
  Req.get!(
    base <> "/electric/v1/user_card",
    params: %{handle: handle, offset: offset},
    headers: [{"accept", "application/json"}],
    receive_timeout: 10_000
  )

# Filter for our specific user
user_hash_hex_encoded = encode_hex.(user_hash)

# Parse response - body should be a list of messages
messages = get_resp.body

retrieved_card =
  messages
  |> Enum.find_value(fn
    %{"value" => %{"user_hash" => hash} = card} when hash == user_hash_hex_encoded -> card
    _ -> nil
  end)

if is_nil(retrieved_card) do
  raise "User card not found after creation"
end

IO.puts("✓ Retrieved user card:")
IO.puts("  Name: #{retrieved_card["name"]}")
IO.puts("  Timestamp: #{retrieved_card["owner_timestamp"]}")
IO.puts("  Deleted: #{retrieved_card["deleted_flag"]}")

# ============================================================================
# STEP 3: UPDATE USER
# ============================================================================
IO.puts("\n[3/4] Updating user name...")

new_name = "Updated Test User #{:rand.uniform(1000)}"
current_timestamp =
  case Map.get(retrieved_card, "owner_timestamp", "0") do
    ts when is_binary(ts) -> String.to_integer(ts)
    ts when is_integer(ts) -> ts
  end
new_timestamp = current_timestamp + 1

# Decode fields from retrieved card
sign_pkey_hex = String.replace_prefix(retrieved_card["sign_pkey"], "\\x", "")
{:ok, sign_pkey_decoded} = Base.decode16(sign_pkey_hex, case: :mixed)

contact_pkey_decoded = Base.decode16!(String.replace_prefix(retrieved_card["contact_pkey"], "\\x", ""), case: :mixed)
contact_cert_decoded = Base.decode16!(String.replace_prefix(retrieved_card["contact_cert"], "\\x", ""), case: :mixed)
crypt_pkey_decoded = Base.decode16!(String.replace_prefix(retrieved_card["crypt_pkey"], "\\x", ""), case: :mixed)
crypt_cert_decoded = Base.decode16!(String.replace_prefix(retrieved_card["crypt_cert"], "\\x", ""), case: :mixed)

# Create signature for update
update_signature_fields = %{
  "contact_cert" => contact_cert_decoded,
  "contact_pkey" => contact_pkey_decoded,
  "crypt_cert" => crypt_cert_decoded,
  "crypt_pkey" => crypt_pkey_decoded,
  "deleted_flag" => false,
  "name" => new_name,
  "owner_timestamp" => new_timestamp,
  "sign_pkey" => sign_pkey_decoded,
  "user_hash" => user_hash
}

update_signature_data =
  update_signature_fields
  |> Enum.sort_by(fn {key, _value} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

update_sign_b64 = :crypto.sign(:mldsa87, :none, update_signature_data, sign_skey)

update_payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => encode_hex.(user_hash)
      },
      "changes" => %{
        "name" => new_name,
        "owner_timestamp" => new_timestamp,
        "sign_b64" => encode_b64.(update_sign_b64)
      },
      "syncMetadata" => %{
        "relation" => "user_cards"
      }
    }
  ]
}

update_challenge_resp =
  Req.get!(
    base <> "/electric/v1/challenge",
    headers: [{"accept", "application/json"}]
  )

%{"challenge" => update_challenge, "challenge_id" => update_challenge_id} = update_challenge_resp.body

update_signature = :crypto.sign(:mldsa87, :none, update_challenge, sign_skey)
update_signature_b64 = Base.encode64(update_signature, padding: false)

update_payload =
  Map.put(update_payload, "auth", %{"challenge_id" => update_challenge_id, "signature" => update_signature_b64})

update_resp =
  Req.post!(
    base <> "/electric/v1/ingest",
    json: update_payload,
    headers: [{"accept", "application/json"}]
  )

if update_resp.status != 200 do
  IO.puts(:stderr, "✗ Failed to update user: #{inspect(update_resp.body)}")
  System.halt(1)
end

IO.puts("✓ Updated user name: #{name} → #{new_name}")

# Wait for propagation through Phoenix.Sync
Process.sleep(5000)

# ============================================================================
# STEP 4: DELETE USER (soft delete via deleted_flag)
# ============================================================================
IO.puts("\n[4/4] Deleting user card...")

delete_timestamp = new_timestamp + 1

delete_signature_fields = %{
  "contact_cert" => contact_cert_decoded,
  "contact_pkey" => contact_pkey_decoded,
  "crypt_cert" => crypt_cert_decoded,
  "crypt_pkey" => crypt_pkey_decoded,
  "deleted_flag" => true,
  "name" => new_name,
  "owner_timestamp" => delete_timestamp,
  "sign_pkey" => sign_pkey_decoded,
  "user_hash" => user_hash
}

delete_signature_data =
  delete_signature_fields
  |> Enum.sort_by(fn {key, _value} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

delete_sign_b64 = :crypto.sign(:mldsa87, :none, delete_signature_data, sign_skey)

delete_payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => encode_hex.(user_hash)
      },
      "changes" => %{
        "deleted_flag" => true,
        "owner_timestamp" => delete_timestamp,
        "sign_b64" => encode_b64.(delete_sign_b64)
      },
      "syncMetadata" => %{
        "relation" => "user_cards"
      }
    }
  ]
}

delete_challenge_resp =
  Req.get!(
    base <> "/electric/v1/challenge",
    headers: [{"accept", "application/json"}]
  )

%{"challenge" => delete_challenge, "challenge_id" => delete_challenge_id} = delete_challenge_resp.body

delete_signature = :crypto.sign(:mldsa87, :none, delete_challenge, sign_skey)
delete_signature_b64 = Base.encode64(delete_signature, padding: false)

delete_payload =
  Map.put(delete_payload, "auth", %{"challenge_id" => delete_challenge_id, "signature" => delete_signature_b64})

delete_resp =
  Req.post!(
    base <> "/electric/v1/ingest",
    json: delete_payload,
    headers: [{"accept", "application/json"}]
  )

if delete_resp.status != 200 do
  IO.puts(:stderr, "✗ Failed to delete user: #{inspect(delete_resp.body)}")
  System.halt(1)
end

IO.puts("✓ Marked user as deleted (deleted_flag = true)")

# Wait for propagation through Phoenix.Sync
Process.sleep(5000)

# Verify deletion
# Step 1: Get handle and offset
verify_resp1 =
  Req.get!(
    base <> "/electric/v1/user_card",
    params: %{offset: "-1"},
    headers: [{"accept", "application/json"}]
  )

verify_handle = List.first(Req.Response.get_header(verify_resp1, "electric-handle"))
verify_offset = List.first(Req.Response.get_header(verify_resp1, "electric-offset"))

if is_nil(verify_handle) or is_nil(verify_offset) do
  raise "Missing electric-handle/electric-offset headers"
end

# Step 2: Fetch actual data
verify_resp =
  Req.get!(
    base <> "/electric/v1/user_card",
    params: %{handle: verify_handle, offset: verify_offset},
    headers: [{"accept", "application/json"}],
    receive_timeout: 10_000
  )

# Filter for our specific user
messages_verify = verify_resp.body

final_card =
  messages_verify
  |> Enum.find_value(fn
    %{"value" => %{"user_hash" => hash} = card} when hash == user_hash_hex_encoded -> card
    _ -> nil
  end)

if is_nil(final_card) do
  raise "User card not found after deletion"
end

IO.puts("  Verified deleted_flag: #{final_card["deleted_flag"]}")

# ============================================================================
# SUMMARY
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("SCENARIO COMPLETE")
IO.puts(String.duplicate("=", 80))
IO.puts("\n✓ All operations successful:")
IO.puts("  1. Created user: #{name}")
IO.puts("  2. Retrieved user card")
IO.puts("  3. Updated name: #{new_name}")
IO.puts("  4. Soft deleted user (deleted_flag = true)")
IO.puts("\nUser hash: #{user_hash_hex}")
IO.puts(String.duplicate("=", 80) <> "\n")
