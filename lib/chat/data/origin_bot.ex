defmodule Chat.Data.OriginBot do
  @moduledoc "Origin bot context for managing review bot records in Postgres"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.OriginBot

  def get_origin_bot(bot_hash) do
    repo().get(OriginBot, bot_hash)
  end

  def list_live_for_origin(origin_hash) do
    from(ob in OriginBot,
      where: ob.origin_hash == ^origin_hash and ob.deleted_flag == false
    )
    |> repo().all()
  end

  def upsert_origin_bot(changeset) do
    repo().insert(changeset,
      on_conflict: origin_bot_upsert_query(),
      conflict_target: :bot_hash,
      allow_stale: true
    )
  end

  defp origin_bot_upsert_query do
    from(ob in OriginBot,
      update: [
        set: [
          secret: fragment("EXCLUDED.secret"),
          encrypted_identity: fragment("EXCLUDED.encrypted_identity"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64"),
          sign_hash: fragment("EXCLUDED.sign_hash")
        ]
      ],
      where:
        is_nil(ob.owner_timestamp) or
          ob.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
