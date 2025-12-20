#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
name = System.get_env("NAME") || "John Doe"

pub_key_bin = :crypto.strong_rand_bytes(32)
pub_key_hex = Base.encode16(pub_key_bin, case: :lower)
pub_key = "\\x" <> pub_key_hex

payload = %{
  "mutations" => [
    %{
      "type" => "insert",
      "modified" => %{
        "name" => name,
        "pub_key" => pub_key
      },
      "syncMetadata" => %{
        "relation" => "users"
      }
    }
  ]
}

resp =
  Req.post!(
    base <> "/electric/v1/ingest",
    json: payload,
    headers: [{"accept", "application/json"}]
  )

IO.puts("pub_key=" <> pub_key)
IO.puts(Jason.encode_to_iodata!(resp.body))
