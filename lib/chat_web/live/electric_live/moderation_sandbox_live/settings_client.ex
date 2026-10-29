defmodule ChatWeb.ElectricLive.ModerationSandboxLive.SettingsClient do
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

  def set_setting(origin_hash, key, value, existing, origin_sign_skey, base_url) do
    timestamp =
      case existing do
        nil -> TimeKeeper.now_unix()
        %{owner_timestamp: ts} -> max(TimeKeeper.now_unix(), ts + 1)
      end

    setting_struct = %OriginSetting{
      origin_hash: origin_hash,
      key: key,
      value: value,
      deleted_flag: false,
      owner_timestamp: timestamp
    }

    mutation =
      case existing do
        nil ->
          insert_mutation(setting_struct, origin_sign_skey)

        _existing ->
          update_mutation(
            origin_hash,
            key,
            %{value: value, deleted_flag: false},
            timestamp,
            origin_sign_skey
          )
      end

    do_ingest(mutation, origin_sign_skey, base_url)
  end

  def tombstone_setting(setting, origin_sign_skey, base_url) do
    new_timestamp = setting.owner_timestamp + 1

    mutation =
      update_mutation(
        setting.origin_hash,
        setting.key,
        %{value: setting.value, deleted_flag: true},
        new_timestamp,
        origin_sign_skey
      )

    do_ingest(mutation, origin_sign_skey, base_url)
  end

  defp insert_mutation(setting_struct, origin_sign_skey) do
    sign_b64 = sign_setting(setting_struct, origin_sign_skey)

    %{
      "type" => "insert",
      "modified" => %{
        "origin_hash" => setting_struct.origin_hash,
        "key" => setting_struct.key,
        "value" => setting_struct.value,
        "deleted_flag" => setting_struct.deleted_flag,
        "owner_timestamp" => setting_struct.owner_timestamp,
        "sign_b64" => encode_base64(sign_b64)
      },
      "syncMetadata" => %{"relation" => "origin_settings"}
    }
  end

  defp update_mutation(origin_hash, key, changes, timestamp, origin_sign_skey) do
    setting_struct = %OriginSetting{
      origin_hash: origin_hash,
      key: key,
      value: changes.value,
      deleted_flag: changes.deleted_flag,
      owner_timestamp: timestamp
    }

    sign_b64 = sign_setting(setting_struct, origin_sign_skey)

    %{
      "type" => "update",
      "original" => %{
        "origin_hash" => origin_hash,
        "key" => key
      },
      "changes" =>
        Map.merge(
          %{
            "owner_timestamp" => timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          changes |> Map.new(fn {k, v} -> {to_string(k), v} end)
        ),
      "syncMetadata" => %{"relation" => "origin_settings"}
    }
  end

  defp do_ingest(mutation, origin_sign_skey, base_url) do
    payload = %{"mutations" => [mutation]}

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
