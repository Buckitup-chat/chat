defmodule Chat.Repo.Migrations.CreateReviewPasswordCandidate do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE review_password_candidate (
      review_hash TEXT NOT NULL,
      sign_hash TEXT NOT NULL,
      origin_hash TEXT NOT NULL,
      password_b64 BYTEA,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      PRIMARY KEY (review_hash, sign_hash),
      CONSTRAINT review_password_candidate_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_password_candidate_sign_hash_format CHECK (sign_hash ~ '^rvps_[a-f0-9]{128}$'),
      CONSTRAINT review_password_candidate_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_password_candidate_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review_password_candidate ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute "CREATE INDEX review_password_candidate_review_hash ON review_password_candidate(review_hash)"
  end

  def down do
    drop table(:review_password_candidate)
  end
end
