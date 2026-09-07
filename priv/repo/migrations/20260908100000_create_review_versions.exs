defmodule Chat.Repo.Migrations.CreateReviewVersions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE review_versions (
      review_hash TEXT NOT NULL,
      sign_hash TEXT NOT NULL,
      origin_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      content_b64 BYTEA NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      parent_sign_hash TEXT,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      PRIMARY KEY (review_hash, sign_hash),
      CONSTRAINT review_versions_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_versions_sign_hash_format CHECK (sign_hash ~ '^rvs_[a-f0-9]{128}$'),
      CONSTRAINT review_versions_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_versions_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_versions_parent_sign_hash_format CHECK (parent_sign_hash IS NULL OR parent_sign_hash ~ '^rvs_[a-f0-9]{128}$')
    )
    """)

    execute("ALTER TABLE review_versions ALTER COLUMN content_b64 SET STORAGE EXTERNAL")
    execute("ALTER TABLE review_versions ALTER COLUMN sign_b64 SET STORAGE EXTERNAL")

    execute("CREATE INDEX review_versions_parent_sign_hash ON review_versions(parent_sign_hash)")

    # FK from master table: review.parent_sign_hash → review_versions.sign_hash
    execute("""
    ALTER TABLE review
      ADD CONSTRAINT review_parent_sign_hash_fkey
      FOREIGN KEY (review_hash, parent_sign_hash)
      REFERENCES review_versions(review_hash, sign_hash)
      ON DELETE RESTRICT
    """)

    # Electric publication
    execute("""
    DO $$ BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE review_versions;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$;
    """)

    # Append-only guarantee
    execute("REVOKE DELETE ON review_versions FROM PUBLIC")
  end

  def down do
    execute("GRANT DELETE ON review_versions TO PUBLIC")
    execute("ALTER TABLE review DROP CONSTRAINT IF EXISTS review_parent_sign_hash_fkey")
    drop(table(:review_versions))
  end
end
