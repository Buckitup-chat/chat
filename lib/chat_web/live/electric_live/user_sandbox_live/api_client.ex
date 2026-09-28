defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClient do
  @moduledoc """
  API client for Electric ingest operations with request/response logging.
  """

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User
  alias Chat.Db

  @doc """
  Creates a new user via the Electric API.

  Returns:
  - `{:ok, %{user: user_map, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def create_user(name, base_url) do
    identity = User.generate_pq_identity(name)
    card = User.extract_pq_card(identity)

    case ingest_user_card(card, identity.sign_skey, base_url) do
      {:ok, _body, logs} ->
        user_data =
          card
          |> Map.from_struct()
          |> Map.put(:user_hash_hex, String.slice(card.user_hash, 2..-1//1))
          |> Map.put(:sign_skey, identity.sign_skey)
          |> Map.put(:crypt_skey, identity.crypt_skey)
          |> Map.put(:contact_skey, identity.contact_skey)

        {:ok, %{user: user_data, log_entries: logs}}

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
    end
  end

  @doc """
  Updates a user's name via the Electric API.

  `existing_card` must be the full UserCard struct with all fields.

  Returns:
  - `{:ok, %{txid: txid, log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def update_user_name(existing_card, sign_skey, new_name, base_url) do
    new_timestamp = existing_card.owner_timestamp + 1

    updated_card_struct =
      struct(UserCard, Map.put(existing_card, :name, new_name))
      |> Map.put(:owner_timestamp, new_timestamp)

    sign_b64 =
      updated_card_struct
      |> Integrity.signature_payload()
      |> then(&:crypto.sign(:mldsa87, :none, &1, sign_skey))

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => existing_card.user_hash
          },
          "changes" => %{
            "name" => new_name,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{
            "relation" => "user_cards"
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
  Soft-deletes a user via the Electric API by setting deleted_flag=true.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def delete_user(user_hash, sign_skey, base_url) do
    # TODO: replace Db.repo() with shape read to comply with HTTP-only rule
    case Db.repo().get(UserCard, user_hash) do
      nil ->
        {:error, %{reason: "User not found", log_entries: []}}

      existing_card ->
        delete_user_with_card(existing_card, user_hash, sign_skey, base_url)
    end
  end

  defp delete_user_with_card(existing_card, user_hash, sign_skey, base_url) do
    new_timestamp = existing_card.owner_timestamp + 1

    updated_card_struct =
      existing_card
      |> Map.put(:deleted_flag, true)
      |> Map.put(:owner_timestamp, new_timestamp)

    sign_b64 =
      updated_card_struct
      |> Integrity.signature_payload()
      |> then(&:crypto.sign(:mldsa87, :none, &1, sign_skey))

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{
            "user_hash" => user_hash
          },
          "changes" => %{
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{
            "relation" => "user_cards"
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
    # TODO: replace Db.repo() with shape read to comply with HTTP-only rule
    case Db.repo().get_by(UserStorage, user_hash: user_hash, uuid: uuid) do
      nil ->
        {:error, %{reason: "Storage entry not found", log_entries: []}}

      existing ->
        update_existing_storage(existing, user_hash, sign_skey, uuid, value_binary, base_url)
    end
  end

  defp update_existing_storage(existing, user_hash, sign_skey, uuid, value_binary, base_url) do
    owner_timestamp = existing.owner_timestamp + 1
    parent_sign_hash = existing.sign_hash

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
    # TODO: replace Db.repo() with shape read to comply with HTTP-only rule
    case Db.repo().get_by(UserStorage, user_hash: user_hash, uuid: uuid) do
      nil ->
        {:error, %{reason: "Storage entry not found", log_entries: []}}

      existing ->
        delete_existing_storage(existing, user_hash, sign_skey, uuid, base_url)
    end
  end

  defp delete_existing_storage(existing, user_hash, sign_skey, uuid, base_url) do
    owner_timestamp = existing.owner_timestamp + 1
    parent_sign_hash = existing.sign_hash

    storage_attrs = %{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: existing.value_b64,
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
  Ingests an imported user's card into the Electric shape.

  Builds a UserCard from the imported identity data, signs it, and sends
  an insert mutation. If the card already exists, the ingest will fail —
  callers should treat that as success.

  Returns:
  - `{:ok, %{log_entries: [log_entry1, log_entry2]}}`
  - `{:error, %{reason: reason, log_entries: [log_entry, ...]}}`
  """
  def ingest_imported_user(user_data, base_url) do
    card_struct = %UserCard{
      user_hash: user_data.user_hash,
      sign_pkey: user_data.sign_pkey,
      contact_pkey: user_data.contact_pkey,
      contact_cert: user_data.contact_cert,
      crypt_pkey: user_data.crypt_pkey,
      crypt_cert: user_data.crypt_cert,
      name: user_data.name,
      deleted_flag: false,
      owner_timestamp: user_data.owner_timestamp
    }

    sign_b64 =
      card_struct
      |> Integrity.signature_payload()
      |> then(&:crypto.sign(:mldsa87, :none, &1, user_data.sign_skey))

    card = %{card_struct | sign_b64: sign_b64}

    case ingest_user_card(card, user_data.sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  # Private helpers

  defp ingest_user_card(card, sign_skey, base_url) do
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "user_hash" => card.user_hash,
            "sign_pkey" => encode_base64(card.sign_pkey),
            "contact_pkey" => encode_base64(card.contact_pkey),
            "contact_cert" => encode_base64(card.contact_cert),
            "crypt_pkey" => encode_base64(card.crypt_pkey),
            "crypt_cert" => encode_base64(card.crypt_cert),
            "name" => card.name,
            "deleted_flag" => card.deleted_flag,
            "owner_timestamp" => card.owner_timestamp,
            "sign_b64" => encode_base64(card.sign_b64)
          },
          "syncMetadata" => %{
            "relation" => "user_cards"
          }
        }
      ]
    }

    ingest(payload, sign_skey, base_url)
  end
end
