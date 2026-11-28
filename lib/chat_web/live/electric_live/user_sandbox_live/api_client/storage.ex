defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClient.Storage do
  @moduledoc "User storage reads and writes over Electric shapes and ingest."

  import ChatWeb.ElectricLive.SandboxHttp
  import ChatWeb.ElectricLive.UserSandboxLive.ApiClient.Rows

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash

  @doc """
  Creates a storage entry via the Electric API.

  `value` should be raw binary data. It will be encoded as base64 in the JSON payload.

  Returns:
  - `{:ok, %{uuid: uuid, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def create_storage(user_hash, sign_skey, uuid, value_binary, base_url) do
    owner_timestamp = Chat.TimeKeeper.now_unix()

    storage_attrs = %{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: value_binary,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: owner_timestamp
    }

    storage_struct = struct(UserStorage, storage_attrs)
    sign_payload = Integrity.signature_payload(storage_struct)
    sign_b64 = :crypto.sign(:mldsa87, :none, sign_payload, sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> UserStorageSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => user_hash,
            "uuid" => uuid,
            "value_b64" => encode_base64(value_binary),
            "deleted_flag" => false,
            "parent_sign_hash" => nil,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{
            "relation" => "user_storage"
          }
        }
      ]
    }

    case ingest(payload, sign_skey, base_url) do
      {:ok, body, logs} -> {:ok, %{uuid: uuid, txid: body["txid"], log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  @doc """
  Updates a storage entry via the Electric API.

  `value_binary` should be raw binary data. It will be encoded as base64 in the JSON payload.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def update_storage(user_hash, sign_skey, uuid, value_binary, base_url) do
    case fetch_storage_row(user_hash, sign_skey, uuid, base_url) do
      {:ok, row} ->
        update_existing_storage(row, user_hash, sign_skey, uuid, value_binary, base_url)

      :not_found ->
        {:error, %{reason: "Storage entry not found", log_entries: []}}
    end
  end

  defp update_existing_storage(row, user_hash, sign_skey, uuid, value_binary, base_url) do
    owner_timestamp = parse_int(row["owner_timestamp"]) + 1
    parent_sign_hash = row["sign_hash"]

    storage_attrs = %{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: value_binary,
      deleted_flag: false,
      parent_sign_hash: parent_sign_hash,
      owner_timestamp: owner_timestamp
    }

    storage_struct = struct(UserStorage, storage_attrs)
    sign_payload = Integrity.signature_payload(storage_struct)
    sign_b64 = :crypto.sign(:mldsa87, :none, sign_payload, sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> UserStorageSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => user_hash,
            "uuid" => uuid
          },
          "changes" => %{
            "value_b64" => encode_base64(value_binary),
            "deleted_flag" => false,
            "parent_sign_hash" => parent_sign_hash,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{
            "relation" => "user_storage"
          }
        }
      ]
    }

    case ingest(payload, sign_skey, base_url) do
      {:ok, body, logs} -> {:ok, %{txid: body["txid"], log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  @doc """
  Soft-deletes a storage entry via the Electric API by setting deleted_flag=true.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def delete_storage(user_hash, sign_skey, uuid, base_url) do
    case fetch_storage_row(user_hash, sign_skey, uuid, base_url) do
      {:ok, row} ->
        delete_existing_storage(row, user_hash, sign_skey, uuid, base_url)

      :not_found ->
        {:error, %{reason: "Storage entry not found", log_entries: []}}
    end
  end

  defp delete_existing_storage(row, user_hash, sign_skey, uuid, base_url) do
    owner_timestamp = parse_int(row["owner_timestamp"]) + 1
    parent_sign_hash = row["sign_hash"]

    storage_attrs = %{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: decode_b64(row["value_b64"]),
      deleted_flag: true,
      parent_sign_hash: parent_sign_hash,
      owner_timestamp: owner_timestamp
    }

    storage_struct = struct(UserStorage, storage_attrs)
    sign_payload = Integrity.signature_payload(storage_struct)
    sign_b64 = :crypto.sign(:mldsa87, :none, sign_payload, sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> UserStorageSignHash.from_binary()

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => user_hash,
            "uuid" => uuid
          },
          "changes" => %{
            "deleted_flag" => true,
            "parent_sign_hash" => parent_sign_hash,
            "owner_timestamp" => owner_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{
            "relation" => "user_storage"
          }
        }
      ]
    }

    case ingest(payload, sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  @doc """
  Fetches all non-deleted storage entries for a user via the Electric shape API.

  Returns:
  - `{:ok, %{items: [storage_item, ...], log_entries: [log_entry, ...]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def fetch_user_storage(user_hash, sign_skey, base_url) do
    where = "user_hash='#{user_hash}'"
    auth = %{user_hash: user_hash, sign_skey: sign_skey}

    case fetch_shape_gated(base_url, "user_storage", where, auth) do
      {:ok, rows, logs} ->
        items =
          rows
          |> Enum.reject(&(&1["deleted_flag"] == "true"))
          |> Enum.map(fn row ->
            value_binary = decode_b64(row["value_b64"])

            %{
              uuid: row["uuid"],
              value_b64: Base.encode64(value_binary),
              size: byte_size(value_binary),
              label: nil
            }
          end)

        {:ok, %{items: items, log_entries: logs}}

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp fetch_storage_row(user_hash, sign_skey, uuid, base_url) do
    where = "user_hash='#{user_hash}' AND uuid='#{uuid}'"
    auth = %{user_hash: user_hash, sign_skey: sign_skey}

    case fetch_shape_gated(base_url, "user_storage", where, auth) do
      {:ok, [row | _], _logs} -> {:ok, row}
      _ -> :not_found
    end
  end
end
