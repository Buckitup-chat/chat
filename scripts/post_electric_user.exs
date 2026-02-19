#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
name = System.get_env("NAME") || "John Doe"

encode_hex = fn bin -> "\\x" <> Base.encode16(bin, case: :lower) end

pub_key_bin = :crypto.strong_rand_bytes(32)
pub_key_hex = Base.encode16(pub_key_bin, case: :lower)
pub_key = "\\x" <> pub_key_hex

{sign_pkey, sign_skey} = :crypto.generate_key(:mldsa87, [])
{crypt_pkey, _crypt_skey} = :crypto.generate_key(:mlkem1024, [])
{contact_pkey, _contact_skey} = :crypto.generate_key(:mldsa44, [])

user_hash = <<0x01>> <> :crypto.hash(:sha3_512, sign_pkey)

crypt_cert = :crypto.sign(:mldsa87, :none, crypt_pkey, sign_skey)
contact_cert = :crypto.sign(:mldsa87, :none, contact_pkey, sign_skey)

payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "user_hash" => encode_hex.(user_hash),
        "sign_pkey" => encode_hex.(sign_pkey),
        "contact_pkey" => encode_hex.(contact_pkey),
        "contact_cert" => encode_hex.(contact_cert),
        "crypt_pkey" => encode_hex.(crypt_pkey),
        "crypt_cert" => encode_hex.(crypt_cert),
        "name" => name
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
IO.puts("challenge_headers=" <> inspect(challenge_resp.headers))
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

IO.puts("pub_key=" <> pub_key)
IO.puts("ingest_status=" <> to_string(resp.status))
IO.puts("ingest_headers=" <> inspect(resp.headers))
IO.puts("ingest_body=" <> inspect(resp.body))

if resp.status == 200 do
  IO.puts("\n✓ Successfully created user card")
  IO.puts("\nTo update this user's name later, save these values:")
  IO.puts("USER_HASH=" <> Base.encode16(user_hash, case: :lower))
  IO.puts("SIGN_SKEY=" <> Base.encode16(sign_skey, case: :lower))
end
