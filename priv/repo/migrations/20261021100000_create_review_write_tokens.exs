defmodule Chat.Repo.Migrations.CreateReviewWriteTokens do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE review_write_tokens (
      nonce               TEXT    NOT NULL,
      origin_hash         TEXT    NOT NULL REFERENCES origins(origin_hash),
      review_bot_hash     TEXT    NOT NULL REFERENCES user_cards(user_hash),
      origin_order_hash   TEXT,
      parent_nonce        TEXT,
      user_hash           TEXT,
      review_hash         TEXT,
      deleted_flag        BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp     BIGINT  NOT NULL,
      sign_b64            BYTEA   NOT NULL,
      sign_hash           TEXT    NOT NULL,
      PRIMARY KEY (nonce),
      CONSTRAINT rwt_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT rwt_review_bot_hash_format CHECK (review_bot_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT rwt_origin_order_hash_format CHECK (origin_order_hash IS NULL OR origin_order_hash ~ '^org_ord_[a-f0-9]{128}$'),
      CONSTRAINT rwt_user_hash_format CHECK (user_hash IS NULL OR user_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT rwt_review_hash_format CHECK (review_hash IS NULL OR review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT rwt_sign_hash_format CHECK (sign_hash ~ '^rwt_[a-f0-9]{128}$')
    )
    """)

    execute("CREATE INDEX rwt_origin_hash_idx ON review_write_tokens (origin_hash)")
    execute("CREATE INDEX rwt_origin_order_hash_idx ON review_write_tokens (origin_order_hash)")
    execute("CREATE INDEX rwt_user_hash_idx ON review_write_tokens (user_hash)")

    execute("ALTER TABLE review_write_tokens ALTER COLUMN sign_b64 SET STORAGE EXTERNAL")

    execute("""
    DO $$ BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE review_write_tokens;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$;
    """)

    execute("REVOKE DELETE ON review_write_tokens FROM PUBLIC")
  end

  def down do
    execute("GRANT DELETE ON review_write_tokens TO PUBLIC")
    drop(table(:review_write_tokens))
  end
end
