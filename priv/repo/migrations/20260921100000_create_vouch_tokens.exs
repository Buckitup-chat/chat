defmodule Chat.Repo.Migrations.CreateVouchTokens do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE vouch_tokens (
      kind         TEXT    NOT NULL,
      issuer_hash  TEXT    NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      subject_hash TEXT    NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      owner_timestamp BIGINT NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      sign_b64     BYTEA   NOT NULL,
      PRIMARY KEY (kind, issuer_hash, subject_hash),
      CONSTRAINT vouch_tokens_issuer_hash_format  CHECK (issuer_hash  ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT vouch_tokens_subject_hash_format CHECK (subject_hash ~ '^u_[a-f0-9]{128}$')
    )
    """)

    execute("ALTER TABLE vouch_tokens ALTER COLUMN sign_b64 SET STORAGE EXTERNAL")

    execute("""
    DO $$ BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE vouch_tokens;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$;
    """)

    execute("REVOKE DELETE ON vouch_tokens FROM PUBLIC")
  end

  def down do
    execute("GRANT DELETE ON vouch_tokens TO PUBLIC")
    drop(table(:vouch_tokens))
  end
end
