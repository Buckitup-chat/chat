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

  @doc """
  Publishes a vouch token. When the `(kind, issuer, subject)` row already exists
  the insert is rejected with 409, so the vouch is re-published as an update
  (re-vouch after revoke, or revoke an existing one via `revoked: true`).
  """
  def create_vouch(identity, subject_hash, kind, base_url, opts \\ []) do
    vouch = %{
      kind: kind,
      subject_hash: subject_hash,
      owner_timestamp: TimeKeeper.now_unix(),
      deleted_flag: Keyword.get(opts, :revoked, false)
    }

    case insert_vouch(identity, vouch, base_url) do
      {:ok, logs} -> {:ok, %{log_entries: logs}}
      {:error, "Ingest failed: 409", logs} -> update_existing(identity, vouch, base_url, logs)
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def revoke_vouch(identity, vouch, base_url) do
    new_timestamp = max(TimeKeeper.now_unix(), vouch.owner_timestamp + 1)

    identity
    |> update_vouch(
      %{vouch | owner_timestamp: new_timestamp} |> Map.put(:deleted_flag, true),
      base_url
    )
    |> case do
      {:ok, logs} -> {:ok, %{owner_timestamp: new_timestamp, log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp update_existing(identity, vouch, base_url, insert_logs) do
    identity.user_hash
    |> list_vouches_by_me(base_url)
    |> Enum.find(&(&1.kind == vouch.kind and &1.subject_hash == vouch.subject_hash))
    |> case do
      nil ->
        {:error,
         %{reason: "Insert conflicted but existing vouch not found", log_entries: insert_logs}}

      existing ->
        timestamp = max(vouch.owner_timestamp, existing.owner_timestamp + 1)

        case update_vouch(identity, %{vouch | owner_timestamp: timestamp}, base_url) do
          {:ok, logs} -> {:ok, %{log_entries: insert_logs ++ logs}}
          {:error, reason, logs} -> {:error, %{reason: reason, log_entries: insert_logs ++ logs}}
        end
    end
  end

  defp insert_vouch(identity, vouch, base_url) do
    %{
      "type" => "insert",
      "modified" => %{
        "kind" => vouch.kind,
        "issuer_hash" => identity.user_hash,
        "subject_hash" => vouch.subject_hash,
        "owner_timestamp" => vouch.owner_timestamp,
        "deleted_flag" => vouch.deleted_flag,
        "sign_b64" => sign(identity, vouch)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
    |> ingest(identity, base_url)
  end

  defp update_vouch(identity, vouch, base_url) do
    %{
      "type" => "update",
      "original" => %{
        "kind" => vouch.kind,
        "issuer_hash" => identity.user_hash,
        "subject_hash" => vouch.subject_hash
      },
      "changes" => %{
        "deleted_flag" => vouch.deleted_flag,
        "owner_timestamp" => vouch.owner_timestamp,
        "sign_b64" => sign(identity, vouch)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
    |> ingest(identity, base_url)
  end

  defp ingest(mutation, identity, base_url) do
    payload = %{"mutations" => [mutation]}

    with {:ok, challenge_resp, log1} <- Http.get_challenge(base_url),
         {:ok, _resp, log2} <-
           Http.post_ingest(challenge_resp, payload, identity.sign_skey, base_url) do
      {:ok, [log1, log2]}
    end
  end

  defp sign(identity, vouch) do
    %VouchToken{
      kind: vouch.kind,
      issuer_hash: identity.user_hash,
      subject_hash: vouch.subject_hash,
      owner_timestamp: vouch.owner_timestamp,
      deleted_flag: vouch.deleted_flag
    }
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(identity.sign_skey)
    |> Http.encode_base64()
  end

  defp parse_vouch_row(row) do
    %{
      kind: row["kind"],
      issuer_hash: row["issuer_hash"],
      subject_hash: row["subject_hash"],
      owner_timestamp: parse_int(row["owner_timestamp"]),
      # snapshot rows carry "true"/"false", change-log rows carry PG text "t"/"f"
      deleted_flag: row["deleted_flag"] in [true, "true", "t"]
    }
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
