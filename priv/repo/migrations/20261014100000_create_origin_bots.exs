defmodule Chat.Repo.Migrations.CreateOriginBots do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE origin_bots (
      bot_hash            TEXT    NOT NULL REFERENCES user_cards(user_hash),
      origin_hash         TEXT    NOT NULL REFERENCES origins(origin_hash),
      secret              BYTEA   NOT NULL,
      encrypted_identity  BYTEA   NOT NULL,
      deleted_flag        BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp     BIGINT  NOT NULL,
      sign_b64            BYTEA   NOT NULL,
      sign_hash           TEXT    NOT NULL,
      PRIMARY KEY (bot_hash),
      CONSTRAINT origin_bots_bot_hash_format CHECK (bot_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT origin_bots_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT origin_bots_sign_hash_format CHECK (sign_hash ~ '^ob_[a-f0-9]{128}$')
    )
    """)

    execute("CREATE INDEX origin_bots_origin_hash_idx ON origin_bots (origin_hash)")

    execute("ALTER TABLE origin_bots ALTER COLUMN sign_b64 SET STORAGE EXTERNAL")
    execute("ALTER TABLE origin_bots ALTER COLUMN secret SET STORAGE EXTERNAL")
    execute("ALTER TABLE origin_bots ALTER COLUMN encrypted_identity SET STORAGE EXTERNAL")

    execute("""
    DO $$ BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE origin_bots;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$;
    """)

    execute("REVOKE DELETE ON origin_bots FROM PUBLIC")
  end

  def down do
    execute("GRANT DELETE ON origin_bots TO PUBLIC")
    drop(table(:origin_bots))
  end
end
