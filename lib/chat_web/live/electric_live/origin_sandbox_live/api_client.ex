defmodule ChatWeb.ElectricLive.OriginSandboxLive.ApiClient do
  @moduledoc "API client for origin Electric ingest operations."

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Types.OriginSignHash
  alias Chat.Data.User
  alias Chat.TimeKeeper
  alias EnigmaPq

  def create_origin(owner, origin_name, moderation_mode, base_url) do
    origin_identity = User.generate_pq_identity(origin_name)
    origin_card = User.extract_pq_card(origin_identity)
    owner_cert = EnigmaPq.sign(origin_card.sign_pkey, owner.sign_skey)

    with {:ok, _body, log1} <- ingest_user_card(origin_card, origin_identity.sign_skey, base_url),
         {:ok, origin_data, log2} <-
           ingest_origin(
             origin_card,
             owner,
             owner_cert,
             origin_name,
             moderation_mode,
             origin_identity.sign_skey,
             base_url
           ) do
      origin_data = Map.put(origin_data, :origin_crypt_skey, origin_identity.crypt_skey)
      {:ok, %{origin: origin_data, log_entries: log1 ++ log2}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def update_origin(origin, owner, new_name, new_mode, base_url) do
    changes = %{name: new_name, moderation_mode: new_mode, deleted_flag: false}
    do_mutate_origin(origin, changes, owner.sign_skey, base_url)
  end

  def delete_origin(origin, owner, base_url) do
    changes = %{name: origin.name, moderation_mode: origin.moderation_mode, deleted_flag: true}
    do_mutate_origin(origin, changes, owner.sign_skey, base_url)
  end

  def list_owner_origins(owner_hash, base_url) do
    case fetch_shape(base_url, "origins", "owner_hash='#{owner_hash}'") do
      {:ok, rows, _log} -> Enum.map(rows, &parse_origin_row/1)
      {:error, _reason, _log} -> []
    end
  end

  def has_pending_reviews?(origin_hash, base_url) do
    with {:ok, reviews, _} <-
           fetch_shape(base_url, "review", "origin_hash='#{origin_hash}'"),
         {:ok, passwords, _} <-
           fetch_shape(base_url, "review_public_passwords", "origin_hash='#{origin_hash}'") do
      password_hashes = MapSet.new(passwords, & &1["review_hash"])

      reviews
      |> Enum.reject(&(&1["deleted_flag"] in [true, "true", "t"]))
      |> Enum.any?(fn r -> r["review_hash"] not in password_hashes end)
    else
      _ -> false
    end
  end

  # --- Private ---

  defp do_mutate_origin(origin, changes, sign_skey, base_url) do
    new_timestamp = origin.owner_timestamp + 1
    mode_str = to_string(changes.moderation_mode)

    origin_struct = %Origin{
      origin_hash: origin.origin_hash,
      owner_hash: origin.owner_hash,
      owner_cert: origin.owner_cert,
      name: changes.name,
      moderation_mode: String.to_existing_atom(mode_str),
      deleted_flag: changes.deleted_flag,
      owner_timestamp: new_timestamp
    }

    {sign_b64, sign_hash} = sign_origin(origin_struct, sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"origin_hash" => origin.origin_hash},
          "changes" => %{
            "name" => changes.name,
            "moderation_mode" => mode_str,
            "deleted_flag" => changes.deleted_flag,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "origins"}
        }
      ]
    }

    case ingest(payload, sign_skey, base_url) do
      {:ok, _body, logs} ->
        updated =
          origin
          |> Map.merge(%{
            name: changes.name,
            moderation_mode: mode_str,
            deleted_flag: changes.deleted_flag,
            owner_timestamp: new_timestamp
          })

        {:ok, %{origin: updated, log_entries: logs}}

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
    end
  end

  defp parse_origin_row(row) do
    %{
      origin_hash: row["origin_hash"],
      owner_hash: row["owner_hash"],
      owner_cert: Base.decode64!(row["owner_cert"], padding: false),
      name: row["name"],
      moderation_mode: row["moderation_mode"],
      deleted_flag: row["deleted_flag"] in [true, "true", "t"],
      owner_timestamp: parse_int(row["owner_timestamp"])
    }
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)

  defp sign_origin(origin_struct, sign_skey) do
    sign_b64 =
      origin_struct
      |> Integrity.signature_payload()
      |> EnigmaPq.sign(sign_skey)

    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> OriginSignHash.from_binary()

    {sign_b64, sign_hash}
  end

  defp ingest_origin(
         origin_card,
         owner,
         owner_cert,
         name,
         moderation_mode,
         origin_sign_skey,
         base_url
       ) do
    origin_struct = %Origin{
      origin_hash: origin_card.user_hash,
      owner_hash: owner.user_hash,
      owner_cert: owner_cert,
      name: name,
      moderation_mode: String.to_existing_atom(moderation_mode),
      deleted_flag: false,
      owner_timestamp: TimeKeeper.now_unix()
    }

    {sign_b64, _sign_hash} = sign_origin(origin_struct, origin_sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => %{
            "origin_hash" => origin_card.user_hash,
            "owner_hash" => owner.user_hash,
            "owner_cert" => encode_base64(owner_cert),
            "name" => name,
            "moderation_mode" => moderation_mode,
            "deleted_flag" => false,
            "owner_timestamp" => origin_struct.owner_timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "origins"}
        }
      ]
    }

    case ingest(payload, origin_sign_skey, base_url) do
      {:ok, _body, logs} ->
        origin_data = %{
          origin_hash: origin_card.user_hash,
          owner_hash: owner.user_hash,
          owner_cert: owner_cert,
          name: name,
          moderation_mode: moderation_mode,
          deleted_flag: false,
          owner_timestamp: origin_struct.owner_timestamp,
          origin_sign_skey: origin_sign_skey
        }

        {:ok, origin_data, logs}

      {:error, _reason, _logs} = error ->
        error
    end
  end

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
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }

    ingest(payload, sign_skey, base_url)
  end
end
