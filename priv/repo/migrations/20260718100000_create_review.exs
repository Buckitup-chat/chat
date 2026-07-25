defmodule Chat.Repo.Migrations.CreateReview do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE review (
      review_hash TEXT PRIMARY KEY,
      origin_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      content_b64 BYTEA NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      parent_sign_hash TEXT,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      sign_hash TEXT NOT NULL,
      CONSTRAINT review_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_sign_hash_format CHECK (sign_hash ~ '^rvs_[a-f0-9]{128}$'),
      CONSTRAINT review_parent_sign_hash_format CHECK (parent_sign_hash IS NULL OR parent_sign_hash ~ '^rvs_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review ALTER COLUMN content_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute "CREATE INDEX review_origin_hash ON review(origin_hash)"
    execute "CREATE INDEX review_author_hash ON review(author_hash)"
  end

  def down do
    drop table(:review)
  end
end
