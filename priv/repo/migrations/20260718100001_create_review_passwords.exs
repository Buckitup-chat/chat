defmodule Chat.Repo.Migrations.CreateReviewPublicPasswords do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE review_public_passwords (
      review_hash TEXT NOT NULL,
      sign_hash TEXT NOT NULL,
      origin_hash TEXT NOT NULL,
      password_b64 BYTEA,
      author_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      PRIMARY KEY (review_hash, sign_hash),
      CONSTRAINT review_public_passwords_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_public_passwords_sign_hash_format CHECK (sign_hash ~ '^rvps_[a-f0-9]{128}$'),
      CONSTRAINT review_public_passwords_origin_hash_format CHECK (origin_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_public_passwords_author_hash_format CHECK (author_hash ~ '^u_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review_public_passwords ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute "CREATE INDEX review_public_passwords_review_hash ON review_public_passwords(review_hash)"
  end

  def down do
    drop table(:review_public_passwords)
  end
end
