#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5.0"}, {:jason, "~> 1.4"}])

base = System.get_env("BASE_URL") || "http://127.0.0.1:4444"
path = "/electric/v1/user_card"

resp1 =
  Req.get!(
    base <> path,
    params: %{offset: "-1"},
    headers: [{"accept", "application/json"}]
  )

handle = List.first(Req.Response.get_header(resp1, "electric-handle"))
offset = List.first(Req.Response.get_header(resp1, "electric-offset"))

if is_nil(handle) or is_nil(offset) do
  raise "Missing electric-handle/electric-offset headers"
end

resp2 =
  Req.get!(
    base <> path,
    params: %{handle: handle, offset: offset},
    headers: [{"accept", "application/json"}]
  )

IO.puts(Jason.encode_to_iodata!(resp2.body))
