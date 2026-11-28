defmodule Chat.Test.SandboxIngestHelpers do
  @moduledoc """
  Sandbox-style ingest flows for review gating tests: every write (origin settings, vouch
  tokens, reviews) goes through `GET /electric/v1/challenge` + `POST /electric/v1/ingest`,
  the same path the sandbox LiveViews use, with mutations built like the sandbox client.
  """

  import Chat.Test.ElectricIngestHelpers, only: [challenge_auth: 3, to_base64: 1]
  import Phoenix.ConnTest
  import Plug.Conn

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.Types.ReviewHash
  alias Chat.Data.Types.ReviewSignHash
  alias Chat.Data.User

  @endpoint ChatWeb.Endpoint

  @doc "Posts `mutations` to `/electric/v1/ingest`, signing a challenge fetched over HTTP."
  def ingest_via_http(conn, mutations, sign_skey) do
    %{"challenge" => challenge, "challenge_id" => challenge_id} = get_challenge(conn)

    conn
    |> put_req_header("content-type", "application/json")
    |> post(
      "/electric/v1/ingest",
      Jason.encode!(%{
        "auth" => challenge_auth(challenge_id, challenge, sign_skey),
        "mutations" => mutations
      })
    )
  end

  @doc "Ingests a fresh review by `author` on `origin_hash`; returns the response conn."
  def post_review_ingest(conn, author, origin_hash) do
    ingest_via_http(conn, [review_insert_mutation(author, origin_hash)], author.sign_skey)
  end

  @doc "Ingests the origin's signed `review_access` setting; crashes unless it gets a txid."
  def set_origin_review_access!(conn, origin_identity, origin_hash, value) do
    mutation =
      origin_setting_insert_mutation(origin_hash, "review_access", value, origin_identity)

    %{"txid" => _} =
      conn
      |> ingest_via_http([mutation], origin_identity.sign_skey)
      |> json_response(200)
  end

  @doc "Ingests a vouch of `kind` from `issuer_identity` to `subject_hash`; crashes unless accepted."
  def ingest_vouch!(conn, issuer_identity, subject_hash, kind) do
    mutation = vouch_insert_mutation(issuer_identity, subject_hash, kind)

    %{"txid" => _} =
      conn
      |> ingest_via_http([mutation], issuer_identity.sign_skey)
      |> json_response(200)
  end

  @doc """
  Revokes a vouch of `kind` with a deleted insert, falling back to an update when the row
  already exists (409); crashes unless one of them is accepted.
  """
  def ingest_vouch_revoke!(conn, issuer_identity, subject_hash, kind) do
    mutation = vouch_insert_mutation(issuer_identity, subject_hash, kind, deleted_flag: true)
    resp = ingest_via_http(conn, [mutation], issuer_identity.sign_skey)

    case resp.status do
      200 ->
        :ok

      409 ->
        update = vouch_update_mutation(issuer_identity, subject_hash, kind, deleted_flag: true)

        %{"txid" => _} =
          conn
          |> ingest_via_http([update], issuer_identity.sign_skey)
          |> json_response(200)
    end
  end

  defp get_challenge(conn) do
    resp = get(conn, "/electric/v1/challenge")
    json_response(resp, 200)
  end

  # --- Mutation builders (mirror sandbox client patterns) ---

  defp origin_setting_insert_mutation(origin_hash, key, value, origin_identity) do
    setting = %OriginSetting{
      origin_hash: origin_hash,
      key: key,
      value: value,
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }

    sign_b64 =
      setting |> Integrity.signature_payload() |> EnigmaPq.sign(origin_identity.sign_skey)

    %{
      "type" => "insert",
      "modified" => %{
        "origin_hash" => origin_hash,
        "key" => key,
        "value" => value,
        "deleted_flag" => false,
        "owner_timestamp" => setting.owner_timestamp,
        "sign_b64" => to_base64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "origin_settings"}
    }
  end

  defp vouch_insert_mutation(issuer_identity, subject_hash, kind, opts \\ []) do
    deleted_flag = Keyword.get(opts, :deleted_flag, false)
    issuer_hash = User.extract_pq_card(issuer_identity).user_hash

    vouch = %VouchToken{
      kind: kind,
      issuer_hash: issuer_hash,
      subject_hash: subject_hash,
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: deleted_flag
    }

    sign_b64 = vouch |> Integrity.signature_payload() |> EnigmaPq.sign(issuer_identity.sign_skey)

    %{
      "type" => "insert",
      "modified" => %{
        "kind" => kind,
        "issuer_hash" => issuer_hash,
        "subject_hash" => subject_hash,
        "owner_timestamp" => vouch.owner_timestamp,
        "deleted_flag" => deleted_flag,
        "sign_b64" => to_base64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
  end

  defp vouch_update_mutation(issuer_identity, subject_hash, kind, opts) do
    deleted_flag = Keyword.get(opts, :deleted_flag, false)
    issuer_hash = User.extract_pq_card(issuer_identity).user_hash
    timestamp = System.os_time(:millisecond) + 1

    vouch = %VouchToken{
      kind: kind,
      issuer_hash: issuer_hash,
      subject_hash: subject_hash,
      owner_timestamp: timestamp,
      deleted_flag: deleted_flag
    }

    sign_b64 = vouch |> Integrity.signature_payload() |> EnigmaPq.sign(issuer_identity.sign_skey)

    %{
      "type" => "update",
      "original" => %{
        "kind" => kind,
        "issuer_hash" => issuer_hash,
        "subject_hash" => subject_hash
      },
      "changes" => %{
        "owner_timestamp" => timestamp,
        "deleted_flag" => deleted_flag,
        "sign_b64" => to_base64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
  end

  defp review_insert_mutation(author, origin_hash) do
    author_card = User.extract_pq_card(author)
    review_hash = :crypto.strong_rand_bytes(64) |> ReviewHash.from_binary()
    content_b64 = EnigmaPq.aes_gcm_encrypt("Great place!", :crypto.strong_rand_bytes(32))
    timestamp = System.os_time(:millisecond)

    review = %Review{
      review_hash: review_hash,
      origin_hash: origin_hash,
      author_hash: author_card.user_hash,
      content_b64: content_b64,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: timestamp
    }

    sign_b64 = review |> Integrity.signature_payload() |> EnigmaPq.sign(author.sign_skey)
    sign_hash = sign_b64 |> EnigmaPq.hash() |> ReviewSignHash.from_binary()

    %{
      "type" => "insert",
      "modified" => %{
        "review_hash" => review_hash,
        "origin_hash" => origin_hash,
        "author_hash" => author_card.user_hash,
        "content_b64" => to_base64(content_b64),
        "deleted_flag" => false,
        "parent_sign_hash" => nil,
        "owner_timestamp" => timestamp,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      },
      "syncMetadata" => %{"relation" => "review"}
    }
  end
end
