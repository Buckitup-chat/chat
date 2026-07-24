defmodule Chat.Data.Origin do
  @moduledoc "Origin context for managing origin entities in Postgres"

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  alias Chat.Data.Schemas.Origin

  def get_origin(origin_hash) do
    repo().get(Origin, origin_hash)
  end

  def upsert_origin(changeset) do
    repo().insert(changeset,
      on_conflict: origin_upsert_query(),
      conflict_target: :origin_hash,
      allow_stale: true
    )
  end

  def update_origin(changeset) do
    repo().update(changeset)
  end

  defp origin_upsert_query do
    from(o in Origin,
      update: [
        set: [
          name: fragment("EXCLUDED.name"),
          moderation_mode: fragment("EXCLUDED.moderation_mode"),
          deleted_flag: fragment("EXCLUDED.deleted_flag"),
          owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
          sign_b64: fragment("EXCLUDED.sign_b64"),
          sign_hash: fragment("EXCLUDED.sign_hash")
        ]
      ],
      where:
        is_nil(o.owner_timestamp) or
          o.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
    )
  end
end
