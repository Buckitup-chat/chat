defmodule Chat.Test.ElectricIngestHelpers do
  @moduledoc "Signed-request, signing and encoding helpers for Electric ingest controller tests."

  import Phoenix.ConnTest
  import Plug.Conn

  alias Chat.Challenge
  alias Chat.Data.Integrity

  @endpoint ChatWeb.Endpoint

  @doc "Base64 without padding, the encoding the ingest endpoints expect for binaries."
  def to_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  @doc "`to_base64/1` that passes `nil` through."
  def maybe_base64(nil), do: nil
  def maybe_base64(bin), do: to_base64(bin)

  @doc "Posts `payload` to `/electric/v1/ingest`, authenticated by `sign_skey`."
  def post_ingest(conn, payload, sign_skey),
    do: post_signed(conn, "/electric/v1/ingest", payload, sign_skey)

  @doc "Posts `payload` to `/electric/v1/ingest_each`, authenticated by `sign_skey`."
  def post_ingest_each(conn, payload, sign_skey),
    do: post_signed(conn, "/electric/v1/ingest_each", payload, sign_skey)

  @doc """
  Posts `payload` as JSON to `path` with an `auth` entry signed over a freshly
  stored challenge (no HTTP round-trip for the challenge).
  """
  def post_signed(conn, path, payload, sign_skey) do
    {challenge_id, challenge} = Challenge.store()

    payload =
      payload
      |> Map.put("auth", challenge_auth(challenge_id, challenge, sign_skey))

    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  @doc "The `auth` map of an ingest request: challenge id and the challenge signed by `sign_skey`."
  def challenge_auth(challenge_id, challenge, sign_skey) do
    %{
      "challenge_id" => challenge_id,
      "signature" => challenge |> EnigmaPq.sign(sign_skey) |> to_base64()
    }
  end

  @doc "Signature over `Integrity.signature_payload/1` of a struct or map."
  def signature_of(struct, sign_skey) do
    struct
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(sign_skey)
  end

  @doc """
  `{sign_b64, sign_hash}` of a struct: its signature and the sign hash type built
  by `hash_fn` (e.g. `&ReviewSignHash.from_binary/1`) from the signature's hash.
  Unlike `Chat.Test.ReviewFixtures.sign_with_hash/3`, the struct is not updated.
  """
  def signature_and_hash(struct, sign_skey, hash_fn) do
    sign_b64 = signature_of(struct, sign_skey)
    {sign_b64, sign_b64 |> EnigmaPq.hash() |> hash_fn.()}
  end
end
