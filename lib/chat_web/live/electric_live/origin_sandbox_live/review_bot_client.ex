defmodule ChatWeb.ElectricLive.OriginSandboxLive.ReviewBotClient do
  @moduledoc "Ingest calls for review bot creation batches."

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Schemas.OriginBot, as: OriginBotSchema
  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.User
  alias Chat.ReviewBot.RowBuilder

  def create_bot(origin_identity, base_url) do
    bot = RowBuilder.generate_identity(origin_identity.name)
    bot_card = User.extract_pq_card(bot)

    with {:ok, _body, card_logs} <- ingest_user_card(bot_card, bot.sign_skey, base_url),
         {:ok, _body, bot_logs} <-
           ingest_origin_bot_and_vouch(bot_card, bot, origin_identity, base_url) do
      {:ok, %{bot: bot, bot_card: bot_card, log_entries: card_logs ++ bot_logs}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def list_origin_bots(origin_hash, base_url, auth) do
    case fetch_shape_gated(base_url, "origin_bots", "origin_hash='#{origin_hash}'", auth) do
      {:ok, rows, _logs} -> Enum.map(rows, &parse_origin_bot_row/1)
      {:error, _reason, _logs} -> []
    end
  end

  def tombstone_bot(bot, origin_sign_skey, base_url) do
    new_timestamp = bot.owner_timestamp + 1

    bot_struct = %OriginBotSchema{
      bot_hash: bot.bot_hash,
      origin_hash: bot.origin_hash,
      secret_b64: bot.secret_b64,
      encrypted_identity_b64: bot.encrypted_identity_b64,
      deleted_flag: true,
      owner_timestamp: new_timestamp
    }

    {sign_b64, sign_hash} = sign_struct(bot_struct, origin_sign_skey, OriginBotSignHash)

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"bot_hash" => bot.bot_hash},
          "changes" => %{
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64),
            "sign_hash" => sign_hash
          },
          "syncMetadata" => %{"relation" => "origin_bots"}
        }
      ]
    }

    case ingest(payload, origin_sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  # --- Private ---

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

  defp ingest_origin_bot_and_vouch(bot_card, bot_identity, origin_identity, base_url) do
    origin_hash = origin_hash_from(origin_identity)

    ob =
      RowBuilder.origin_bot(
        bot_card.user_hash,
        bot_identity,
        origin_hash,
        origin_identity.crypt_pkey,
        origin_identity.sign_skey
      )

    vouch =
      RowBuilder.origin_vouch(origin_hash, origin_identity.sign_skey, bot_card.user_hash)

    payload = %{
      "mutations" => [
        origin_bot_mutation(ob),
        vouch_mutation(vouch, origin_hash)
      ]
    }

    ingest(payload, origin_identity.sign_skey, base_url)
  end

  defp origin_bot_mutation(ob) do
    %{
      "type" => "insert",
      "modified" => %{
        "bot_hash" => ob.bot_hash,
        "origin_hash" => ob.origin_hash,
        "secret_b64" => encode_base64(ob.secret_b64),
        "encrypted_identity_b64" => encode_base64(ob.encrypted_identity_b64),
        "deleted_flag" => ob.deleted_flag,
        "owner_timestamp" => ob.owner_timestamp,
        "sign_b64" => encode_base64(ob.sign_b64),
        "sign_hash" => ob.sign_hash
      },
      "syncMetadata" => %{"relation" => "origin_bots"}
    }
  end

  defp vouch_mutation(vouch, origin_hash) do
    %{
      "type" => "insert",
      "modified" => %{
        "kind" => vouch.kind,
        "issuer_hash" => origin_hash,
        "subject_hash" => vouch.subject_hash,
        "owner_timestamp" => vouch.owner_timestamp,
        "deleted_flag" => vouch.deleted_flag,
        "sign_b64" => encode_base64(vouch.sign_b64)
      },
      "syncMetadata" => %{"relation" => "vouch_tokens"}
    }
  end

  defp origin_hash_from(%{origin_hash: hash}), do: hash

  defp origin_hash_from(identity) do
    identity.sign_pkey
    |> EnigmaPq.hash()
    |> Chat.Data.Types.UserHash.from_binary()
  end

  defp parse_origin_bot_row(row) do
    %{
      bot_hash: row["bot_hash"],
      origin_hash: row["origin_hash"],
      secret_b64: decode_binary(row["secret_b64"]),
      encrypted_identity_b64: decode_binary(row["encrypted_identity_b64"]),
      deleted_flag: row["deleted_flag"] in [true, "true", "t"],
      owner_timestamp: parse_int(row["owner_timestamp"]),
      sign_hash: row["sign_hash"]
    }
  end

  defp decode_binary(nil), do: nil
  defp decode_binary(val) when is_binary(val), do: Base.decode64!(val, padding: false)

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)
end
