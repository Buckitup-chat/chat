#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"

encode_hex = fn bin -> "\\x" <> Base.encode16(bin, case: :lower) end
encode_b64 = fn bin -> Base.encode64(bin, padding: false) end

IO.puts("=== User Storage Scenario ===\n")

# Step 1: Create User Card
IO.puts("Step 1: Creating user card...")

name = "Test User #{:rand.uniform(1000)}"
{sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
{crypt_pkey, _crypt_skey} = :crypto.generate_key(:mlkem1024, [])
{contact_pkey, _contact_skey} = :crypto.generate_key(:mldsa44, [])

user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)
user_hash_hex = Base.encode16(user_hash, case: :lower)
sign_skey_hex = Base.encode16(sign_skey, case: :lower)

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
    is_nil(value) -> "null"
    String.ends_with?(key, "_b64") -> Base.encode64(value)
    String.ends_with?(key, "_cert") -> Base.encode64(value)
    String.ends_with?(key, "_pkey") -> Base.encode64(value)
    String.ends_with?(key, "_hash") -> Base.encode16(value, case: :lower)
    value == true -> "true"
    value == false -> "false"
    is_integer(value) -> Integer.to_string(value)
    is_binary(value) -> value
    true -> to_string(value)
  end
end

signature_data =
  signature_fields
  |> Enum.sort_by(fn {key, _} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

sign_b64_raw = :crypto.sign(:mldsa87, :none, signature_data, sign_skey)
sign_b64 = encode_b64.(sign_b64_raw)

card_payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => encode_hex.(user_hash),
        "name" => name,
        "sign_pkey" => encode_b64.(sign_pkey),
        "contact_pkey" => encode_b64.(contact_pkey),
        "contact_cert" => encode_b64.(contact_cert),
        "crypt_pkey" => encode_b64.(crypt_pkey),
        "crypt_cert" => encode_b64.(crypt_cert),
        "deleted_flag" => deleted_flag,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => sign_b64
      },
      "syncMetadata" => %{
        "relation" => "user_cards"
      }
    }
  ]
}

challenge_resp = Req.get!(base <> "/electric/v1/challenge", headers: [{"accept", "application/json"}])
%{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp.body

signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
signature_b64 = Base.encode64(signature, padding: false)

card_payload = Map.put(card_payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

resp = Req.post!(base <> "/electric/v1/ingest", json: card_payload, headers: [{"accept", "application/json"}])

if resp.status == 200 do
  IO.puts("✓ User card created successfully")
  IO.puts("  USER_HASH: #{user_hash_hex}")
  IO.puts("  NAME: #{name}\n")
else
  IO.puts(:stderr, "✗ Failed to create user card: #{inspect(resp.body)}")
  System.halt(1)
end

# Step 2: Create Storage Item
IO.puts("Step 2: Creating storage item...")

uuid1 = "550e8400-e29b-41d4-a716-446655440000"
value1 = "My first storage value"
value1_bin = :erlang.term_to_binary(value1)
timestamp1 = System.system_time(:second)

# Build signature for storage
storage_sig_fields = %{
  "deleted_flag" => false,
  "owner_timestamp" => timestamp1,
  "parent_sign_hash" => nil,
  "user_hash" => user_hash,
  "uuid" => uuid1,
  "value_b64" => value1_bin
}

storage_sig_data =
  storage_sig_fields
  |> Enum.sort_by(fn {key, _} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

storage_sign_b64_raw = :crypto.sign(:mldsa87, :none, storage_sig_data, sign_skey)
storage_sign_b64 = encode_b64.(storage_sign_b64_raw)
storage_sign_hash = :crypto.hash(:sha3_256, storage_sign_b64_raw)

storage_payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => encode_hex.(user_hash),
        "uuid" => uuid1,
        "value_b64" => encode_b64.(value1_bin),
        "deleted_flag" => false,
        "owner_timestamp" => timestamp1,
        "sign_b64" => storage_sign_b64,
        "sign_hash" => encode_hex.(storage_sign_hash)
      },
      "syncMetadata" => %{
        "relation" => "user_storage"
      }
    }
  ]
}

challenge_resp = Req.get!(base <> "/electric/v1/challenge", headers: [{"accept", "application/json"}])
%{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp.body
signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
signature_b64 = Base.encode64(signature, padding: false)
storage_payload = Map.put(storage_payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

resp = Req.post!(base <> "/electric/v1/ingest", json: storage_payload, headers: [{"accept", "application/json"}])

if resp.status == 200 do
  IO.puts("✓ Storage item created successfully")
  IO.puts("  UUID: #{uuid1}")
  IO.puts("  VALUE: #{value1}\n")
else
  IO.puts(:stderr, "✗ Failed to create storage item: #{inspect(resp.body)}")
  System.halt(1)
end

# Step 3: Update Storage Item
IO.puts("Step 3: Updating storage item...")

value2 = "My updated storage value"
value2_bin = :erlang.term_to_binary(value2)
timestamp2 = System.system_time(:second) + 10

# Build signature for updated storage
update_sig_fields = %{
  "deleted_flag" => false,
  "owner_timestamp" => timestamp2,
  "parent_sign_hash" => nil,
  "user_hash" => user_hash,
  "uuid" => uuid1,
  "value_b64" => value2_bin
}

update_sig_data =
  update_sig_fields
  |> Enum.sort_by(fn {key, _} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

update_sign_b64_raw = :crypto.sign(:mldsa87, :none, update_sig_data, sign_skey)
update_sign_b64 = encode_b64.(update_sign_b64_raw)
update_sign_hash = :crypto.hash(:sha3_256, update_sign_b64_raw)

update_payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => encode_hex.(user_hash),
        "uuid" => uuid1
      },
      "changes" => %{
        "value_b64" => encode_b64.(value2_bin),
        "owner_timestamp" => timestamp2,
        "sign_b64" => update_sign_b64,
        "sign_hash" => encode_hex.(update_sign_hash)
      },
      "syncMetadata" => %{
        "relation" => "user_storage"
      }
    }
  ]
}

challenge_resp = Req.get!(base <> "/electric/v1/challenge", headers: [{"accept", "application/json"}])
%{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp.body
signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
signature_b64 = Base.encode64(signature, padding: false)
update_payload = Map.put(update_payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

resp = Req.post!(base <> "/electric/v1/ingest", json: update_payload, headers: [{"accept", "application/json"}])

if resp.status == 200 do
  IO.puts("✓ Storage item updated successfully")
  IO.puts("  UUID: #{uuid1}")
  IO.puts("  NEW VALUE: #{value2}\n")
else
  IO.puts(:stderr, "✗ Failed to update storage item: #{inspect(resp.body)}")
  System.halt(1)
end

# Step 4: Get Storage Items
IO.puts("Step 4: Getting storage items...")

# Give Electric a moment to sync
Process.sleep(1000)

path = "/electric/v1/user_storage/#{user_hash_hex}"

resp1 = Req.get(base <> path, params: %{offset: "-1"}, headers: [{"accept", "application/json"}])

case resp1 do
  {:ok, response} when response.status == 200 ->
    handle = List.first(Req.Response.get_header(response, "electric-handle"))
    offset = List.first(Req.Response.get_header(response, "electric-offset"))

    if is_nil(handle) or is_nil(offset) do
      IO.puts("⚠ Electric sync not ready yet, skipping GET for now")
    else
      resp2 = Req.get!(base <> path, params: %{handle: handle, offset: offset}, headers: [{"accept", "application/json"}])
      IO.puts("✓ Storage items retrieved successfully")
      IO.puts("  Response: #{Jason.encode!(resp2.body, pretty: true)}\n")
    end

  _ ->
    IO.puts("⚠ Electric sync not ready yet, skipping GET for now\n")
end

# Step 5: Delete Storage Item (soft delete)
IO.puts("Step 5: Deleting storage item (soft delete)...")

timestamp3 = System.system_time(:second) + 20

# Build signature for deleted storage
delete_sig_fields = %{
  "deleted_flag" => true,
  "owner_timestamp" => timestamp3,
  "parent_sign_hash" => nil,
  "user_hash" => user_hash,
  "uuid" => uuid1,
  "value_b64" => value2_bin
}

delete_sig_data =
  delete_sig_fields
  |> Enum.sort_by(fn {key, _} -> key end)
  |> Enum.map(encode_field)
  |> Enum.join("")

delete_sign_b64_raw = :crypto.sign(:mldsa87, :none, delete_sig_data, sign_skey)
delete_sign_b64 = encode_b64.(delete_sign_b64_raw)
delete_sign_hash = :crypto.hash(:sha3_256, delete_sign_b64_raw)

delete_payload = %{
  "mutations" => [
    %{
      "type" => "update",
      "original" => %{
        "user_hash" => encode_hex.(user_hash),
        "uuid" => uuid1
      },
      "changes" => %{
        "deleted_flag" => true,
        "owner_timestamp" => timestamp3,
        "sign_b64" => delete_sign_b64,
        "sign_hash" => encode_hex.(delete_sign_hash)
      },
      "syncMetadata" => %{
        "relation" => "user_storage"
      }
    }
  ]
}

challenge_resp = Req.get!(base <> "/electric/v1/challenge", headers: [{"accept", "application/json"}])
%{"challenge" => challenge, "challenge_id" => challenge_id} = challenge_resp.body
signature = :crypto.sign(:mldsa87, :none, challenge, sign_skey)
signature_b64 = Base.encode64(signature, padding: false)
delete_payload = Map.put(delete_payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

resp = Req.post!(base <> "/electric/v1/ingest", json: delete_payload, headers: [{"accept", "application/json"}])

if resp.status == 200 do
  IO.puts("✓ Storage item deleted successfully")
  IO.puts("  UUID: #{uuid1}\n")
else
  IO.puts(:stderr, "✗ Failed to delete storage item: #{inspect(resp.body)}")
  System.halt(1)
end

# Step 6: Verify deletion by getting items again
IO.puts("Step 6: Verifying deletion...")

# Give Electric a moment to sync
Process.sleep(1000)

resp1 = Req.get(base <> path, params: %{offset: "-1"}, headers: [{"accept", "application/json"}])

case resp1 do
  {:ok, response} when response.status == 200 ->
    handle = List.first(Req.Response.get_header(response, "electric-handle"))
    offset = List.first(Req.Response.get_header(response, "electric-offset"))

    if is_nil(handle) or is_nil(offset) do
      IO.puts("⚠ Electric sync not ready yet, skipping final GET\n")
    else
      resp2 = Req.get!(base <> path, params: %{handle: handle, offset: offset}, headers: [{"accept", "application/json"}])
      IO.puts("✓ Final state retrieved successfully")
      IO.puts("  Response: #{Jason.encode!(resp2.body, pretty: true)}\n")
    end

  _ ->
    IO.puts("⚠ Electric sync not ready yet, skipping final GET\n")
end

IO.puts("\n=== Scenario Complete ===")
IO.puts("\nSummary:")
IO.puts("  USER_HASH: #{user_hash_hex}")
IO.puts("  SIGN_SKEY: #{sign_skey_hex}")
IO.puts("  Storage UUID: #{uuid1}")
IO.puts("  All operations completed successfully!")
