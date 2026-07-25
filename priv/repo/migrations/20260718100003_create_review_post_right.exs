defmodule Chat.Repo.Migrations.CreateReviewPostRight do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE review_post_right (
      review_hash TEXT PRIMARY KEY,
      origin_hash TEXT NOT NULL,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      kem_ciphertext_b64 BYTEA NOT NULL,
      wrapped_row_b64 BYTEA NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA,
      sign_hash TEXT,
      CONSTRAINT review_post_right_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_post_right_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_post_right_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_post_right_sign_hash_format CHECK (sign_hash IS NULL OR sign_hash ~ '^rvprs_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review_post_right ALTER COLUMN kem_ciphertext_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_post_right ALTER COLUMN wrapped_row_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_post_right ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"
  end

  def down do
    drop table(:review_post_right)
  end
end
