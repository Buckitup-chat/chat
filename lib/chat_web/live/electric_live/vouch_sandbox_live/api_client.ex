defmodule ChatWeb.ElectricLive.VouchSandboxLive.ApiClient do
  @moduledoc "API client for vouch token Electric ingest operations."

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.VouchToken
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.OriginSandboxLive.Http
  alias ChatWeb.ElectricLive.ShapeReader

  def list_users(base_url) do
    client = Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")
    shape = Electric.Client.ShapeDefinition.new!("user_cards")

    ShapeReader.collect(client, shape)
    |> Enum.map(fn row ->
      %{user_hash: row["user_hash"], name: row["name"]}
    end)
    |> Enum.reject(&(&1.name == nil or &1.name == ""))
    |> Enum.sort_by(& &1.name)
  end

  def list_vouches_by_me(issuer_hash, base_url) do
    client = Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")

    shape =
      Electric.Client.ShapeDefinition.new!("vouch_tokens",
        where: "issuer_hash = $1",
        params: [issuer_hash]
      )

    ShapeReader.collect(client, shape)
    |> Enum.map(&parse_vouch_row/1)
    |> Enum.sort_by(& &1.owner_timestamp, :desc)
  end

  def list_vouches_for_me(subject_hash, base_url) do
    client = Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")

    shape =
      Electric.Client.ShapeDefinition.new!("vouch_tokens",
        where: "subject_hash = $1",
        params: [subject_hash]
      )

    ShapeReader.collect(client, shape)
    |> Enum.map(&parse_vouch_row/1)
    |> Enum.sort_by(& &1.owner_timestamp, :desc)
  end

  def create_vouch(identity, subject_hash, kind, base_url) do
    timestamp = TimeKeeper.now_unix()

    vt_struct = %VouchToken{
      kind: kind,
      issuer_hash: identity.user_hash,
      subject_hash: subject_hash,
      owner_timestamp: timestamp,
      deleted_flag: false
    }

    sign_b64 =
      vt_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "kind" => kind,
            "issuer_hash" => identity.user_hash,
            "subject_hash" => subject_hash,
            "owner_timestamp" => timestamp,
            "deleted_flag" => false,
            "sign_b64" => Http.encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "vouch_tokens"}
        }
      ]
    }

    with {:ok, challenge_resp, log1} <- Http.get_challenge(base_url),
         {:ok, _resp, log2} <- Http.post_ingest(challenge_resp, payload, identity.sign_skey, base_url) do
      {:ok, %{log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def revoke_vouch(identity, vouch, base_url) do
    new_timestamp = vouch.owner_timestamp + 1

    vt_struct = %VouchToken{
      kind: vouch.kind,
      issuer_hash: identity.user_hash,
      subject_hash: vouch.subject_hash,
      owner_timestamp: new_timestamp,
      deleted_flag: true
    }

    sign_b64 =
      vt_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(identity.sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "kind" => vouch.kind,
            "issuer_hash" => identity.user_hash,
            "subject_hash" => vouch.subject_hash
          },
          "changes" => %{
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => Http.encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "vouch_tokens"}
        }
      ]
    }

    with {:ok, challenge_resp, log1} <- Http.get_challenge(base_url),
         {:ok, _resp, log2} <- Http.post_ingest(challenge_resp, payload, identity.sign_skey, base_url) do
      {:ok, %{log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp parse_vouch_row(row) do
    %{
      kind: row["kind"],
      issuer_hash: row["issuer_hash"],
      subject_hash: row["subject_hash"],
      owner_timestamp: parse_int(row["owner_timestamp"]),
      deleted_flag: row["deleted_flag"] == true or row["deleted_flag"] == "true"
    }
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
