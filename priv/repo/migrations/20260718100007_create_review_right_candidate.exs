defmodule Chat.Repo.Migrations.CreateReviewRightCandidate do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE review_post_right_candidate (
      review_hash TEXT PRIMARY KEY,
      origin_hash TEXT NOT NULL,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      kem_ciphertext_b64 BYTEA NOT NULL,
      wrapped_row_b64 BYTEA NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA,
      sign_hash TEXT,
      inserted_at BIGINT NOT NULL,
      CONSTRAINT review_post_right_candidate_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_post_right_candidate_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_post_right_candidate_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_post_right_candidate_sign_hash_format CHECK (sign_hash IS NULL OR sign_hash ~ '^rvprs_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review_post_right_candidate ALTER COLUMN kem_ciphertext_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_post_right_candidate ALTER COLUMN wrapped_row_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_post_right_candidate ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute """
    CREATE TABLE review_revoke_right_candidate (
      review_hash TEXT PRIMARY KEY,
      origin_hash TEXT NOT NULL,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      kem_ciphertext_b64 BYTEA NOT NULL,
      wrapped_row_b64 BYTEA NOT NULL,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA,
      sign_hash TEXT,
      inserted_at BIGINT NOT NULL,
      CONSTRAINT review_revoke_right_candidate_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_revoke_right_candidate_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_revoke_right_candidate_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_revoke_right_candidate_sign_hash_format CHECK (sign_hash IS NULL OR sign_hash ~ '^rvrrs_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review_revoke_right_candidate ALTER COLUMN kem_ciphertext_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_revoke_right_candidate ALTER COLUMN wrapped_row_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_revoke_right_candidate ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute "CREATE INDEX review_post_right_candidate_inserted_at ON review_post_right_candidate(inserted_at)"
    execute "CREATE INDEX review_revoke_right_candidate_inserted_at ON review_revoke_right_candidate(inserted_at)"
  end

  def down do
    drop table(:review_post_right_candidate)
    drop table(:review_revoke_right_candidate)
  end
end
