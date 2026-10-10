defmodule ChatWeb.ElectricLive.VouchSandboxLive.ApiClient do
  @moduledoc "API client for vouch token Electric ingest operations."

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.VouchToken
  alias Chat.TimeKeeper

  def list_users(base_url, auth) do
    case fetch_shape_gated(base_url, "user_cards", auth) do
      {:ok, rows, _logs} ->
        rows
        |> Enum.map(fn row -> %{user_hash: row["user_hash"], name: row["name"]} end)
        |> Enum.reject(&(&1.name == nil or &1.name == ""))
        |> Enum.sort_by(& &1.name)

      {:error, _reason, _logs} ->
        []
    end
  end

  def list_vouches_by_me(issuer_hash, base_url, auth) do
    case fetch_shape_gated(base_url, "vouch_tokens", "issuer_hash='#{issuer_hash}'", auth) do
      {:ok, rows, _logs} ->
        rows |> Enum.map(&parse_vouch_row/1) |> Enum.sort_by(& &1.owner_timestamp, :desc)

      {:error, _reason, _logs} ->
        []
    end
  end

  def list_vouches_for_me(subject_hash, base_url, auth) do
    case fetch_shape_gated(base_url, "vouch_tokens", "subject_hash='#{subject_hash}'", auth) do
      {:ok, rows, _logs} ->
        rows |> Enum.map(&parse_vouch_row/1) |> Enum.sort_by(& &1.owner_timestamp, :desc)

      {:error, _reason, _logs} ->
        []
    end
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

    auth = %{user_hash: identity.user_hash, sign_skey: identity.sign_skey}

    case insert_vouch(identity, vouch, base_url) do
      {:ok, logs} ->
        {:ok, %{log_entries: logs}}

      {:error, "Ingest failed: 409", logs} ->
        update_existing(identity, vouch, base_url, logs, auth)

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
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

  defp update_existing(identity, vouch, base_url, insert_logs, auth) do
    identity.user_hash
    |> list_vouches_by_me(base_url, auth)
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
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "kind" => vouch.kind,
            "issuer_hash" => identity.user_hash,
            "subject_hash" => vouch.subject_hash,
            "owner_timestamp" => vouch.owner_timestamp,
            "deleted_flag" => vouch.deleted_flag,
            "sign_b64" => sign_vouch(identity, vouch)
          },
          "syncMetadata" => %{"relation" => "vouch_tokens"}
        }
      ]
    }

    case ingest(payload, identity.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, logs}
      {:error, _reason, _logs} = error -> error
    end
  end

  defp update_vouch(identity, vouch, base_url) do
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
            "deleted_flag" => vouch.deleted_flag,
            "owner_timestamp" => vouch.owner_timestamp,
            "sign_b64" => sign_vouch(identity, vouch)
          },
          "syncMetadata" => %{"relation" => "vouch_tokens"}
        }
      ]
    }

    case ingest(payload, identity.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, logs}
      {:error, _reason, _logs} = error -> error
    end
  end

  defp sign_vouch(identity, vouch) do
    %VouchToken{
      kind: vouch.kind,
      issuer_hash: identity.user_hash,
      subject_hash: vouch.subject_hash,
      owner_timestamp: vouch.owner_timestamp,
      deleted_flag: vouch.deleted_flag
    }
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(identity.sign_skey)
    |> encode_base64()
  end

  defp parse_vouch_row(row) do
    %{
      kind: row["kind"],
      issuer_hash: row["issuer_hash"],
      subject_hash: row["subject_hash"],
      owner_timestamp: parse_int(row["owner_timestamp"]),
      deleted_flag: row["deleted_flag"] in [true, "true", "t"]
    }
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
