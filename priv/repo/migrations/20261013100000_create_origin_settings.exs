defmodule Chat.Repo.Migrations.CreateOriginSettings do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE origin_settings (
      origin_hash     TEXT    NOT NULL REFERENCES origins(origin_hash) ON DELETE CASCADE,
      key             TEXT    NOT NULL,
      value           TEXT    NOT NULL,
      deleted_flag    BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT  NOT NULL,
      sign_b64        BYTEA   NOT NULL,
      PRIMARY KEY (origin_hash, key),
      CONSTRAINT origin_settings_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$')
    )
    """)

    execute("ALTER TABLE origin_settings ALTER COLUMN sign_b64 SET STORAGE EXTERNAL")

    execute("""
    DO $$ BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE origin_settings;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$;
    """)

    execute("REVOKE DELETE ON origin_settings FROM PUBLIC")
  end

  def down do
    execute("GRANT DELETE ON origin_settings TO PUBLIC")
    drop(table(:origin_settings))
  end
end
