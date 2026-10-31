defmodule Chat.Data.OriginSetting do
  @moduledoc "Origin setting context for managing per-origin key-value settings in Postgres"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.OriginSetting

  def get_origin_setting(origin_hash, key) do
    repo().get_by(OriginSetting, origin_hash: origin_hash, key: key)
  end

  def upsert_origin_setting(changeset) do
    repo().insert(changeset,
      on_conflict: origin_setting_upsert_query(),
      conflict_target: [:origin_hash, :key],
      allow_stale: true
    )
  end

  def get_review_access(origin_hash) do
    case get_origin_setting(origin_hash, "review_access") do
      %OriginSetting{deleted_flag: false, value: value} -> value
      _ -> "open"
    end
  end

  def get_review_token_ttl_days(origin_hash) do
    with %OriginSetting{deleted_flag: false, value: value} <-
           get_origin_setting(origin_hash, "review_token_ttl_days"),
         {days, ""} when days >= 1 <- Integer.parse(value) do
      days
    else
      _ -> 7
    end
  end

  defp origin_setting_upsert_query do
    from(os in OriginSetting,
      update: [
        set: [
          value: fragment("EXCLUDED.value"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64")
        ]
      ],
      where:
        is_nil(os.owner_timestamp) or
          os.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
