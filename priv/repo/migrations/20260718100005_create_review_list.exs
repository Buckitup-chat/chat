defmodule Chat.Repo.Migrations.CreateReviewList do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE review_list (
      user_hash TEXT NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      review_hash TEXT NOT NULL,
      password_b64 BYTEA NOT NULL,
      review_password_sign_hash TEXT,
      post_right_sign_hash TEXT,
      revoke_right_sign_hash TEXT,
      deleted_flag BOOLEAN NOT NULL DEFAULT false,
      owner_timestamp BIGINT NOT NULL,
      sign_b64 BYTEA NOT NULL,
      sign_hash TEXT NOT NULL,
      PRIMARY KEY (user_hash, review_hash),
      CONSTRAINT review_list_user_hash_format CHECK (user_hash ~ '^u_[a-f0-9]{128}$'),
      CONSTRAINT review_list_review_hash_format CHECK (review_hash ~ '^rv_[a-f0-9]{128}$'),
      CONSTRAINT review_list_sign_hash_format CHECK (sign_hash ~ '^rvls_[a-f0-9]{128}$'),
      CONSTRAINT review_list_review_password_sign_hash_format CHECK (review_password_sign_hash IS NULL OR review_password_sign_hash ~ '^rvps_[a-f0-9]{128}$'),
      CONSTRAINT review_list_post_right_sign_hash_format CHECK (post_right_sign_hash IS NULL OR post_right_sign_hash ~ '^rvprs_[a-f0-9]{128}$'),
      CONSTRAINT review_list_revoke_right_sign_hash_format CHECK (revoke_right_sign_hash IS NULL OR revoke_right_sign_hash ~ '^rvrrs_[a-f0-9]{128}$')
    )
    """

    execute "ALTER TABLE review_list ALTER COLUMN password_b64 SET STORAGE EXTERNAL"
    execute "ALTER TABLE review_list ALTER COLUMN sign_b64 SET STORAGE EXTERNAL"

    execute "CREATE INDEX review_list_user_hash ON review_list(user_hash)"
  end

  def down do
    drop table(:review_list)
  end
end
