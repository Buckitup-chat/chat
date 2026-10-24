defmodule ChatWeb.ElectricLive.OriginSandboxLive.SettingsClient do
  @moduledoc "HTTP client for origin_settings reads and writes in the origin sandbox."

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.TimeKeeper

  def list_settings(origin_hash, base_url, auth) do
    case fetch_shape_gated(base_url, "origin_settings", "origin_hash='#{origin_hash}'", auth) do
      {:ok, rows, logs} -> {:ok, Enum.map(rows, &parse_setting_row/1), logs}
      {:error, _reason, _logs} = error -> error
    end
  end

  def set_setting(origin_hash, key, value, origin_sign_skey, base_url) do
    timestamp = TimeKeeper.now_unix()

    setting_struct = %OriginSetting{
      origin_hash: origin_hash,
      key: key,
      value: value,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    sign_b64 = sign_setting(setting_struct, origin_sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "origin_hash" => origin_hash,
            "key" => key,
            "value" => value,
            "deleted_flag" => false,
            "owner_timestamp" => timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "origin_settings"}
        }
      ]
    }

    case ingest(payload, origin_sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def tombstone_setting(setting, origin_sign_skey, base_url) do
    new_timestamp = setting.owner_timestamp + 1

    setting_struct = %OriginSetting{
      origin_hash: setting.origin_hash,
      key: setting.key,
      value: setting.value,
      deleted_flag: true,
      owner_timestamp: new_timestamp
    }

    sign_b64 = sign_setting(setting_struct, origin_sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "origin_hash" => setting.origin_hash,
            "key" => setting.key
          },
          "changes" => %{
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "origin_settings"}
        }
      ]
    }

    case ingest(payload, origin_sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp sign_setting(setting_struct, sign_skey) do
    setting_struct
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(sign_skey)
  end

  defp parse_setting_row(row) do
    %{
      origin_hash: row["origin_hash"],
      key: row["key"],
      value: row["value"],
      deleted_flag: row["deleted_flag"] in [true, "true", "t"],
      owner_timestamp: parse_int(row["owner_timestamp"])
    }
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
