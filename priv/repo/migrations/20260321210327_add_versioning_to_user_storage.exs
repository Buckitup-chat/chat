defmodule Chat.Repo.Migrations.AddVersioningToUserStorage do
  use Ecto.Migration

  def change do
    # Create user_storage_versions table first (needed for FK reference)
    execute """
    CREATE TABLE user_storage_versions (
      user_hash user_hash NOT NULL REFERENCES user_cards(user_hash) ON DELETE CASCADE,
      uuid uuid NOT NULL,
      sign_hash bytea NOT NULL,
      value_b64 bytea NOT NULL,
      deleted_flag boolean NOT NULL DEFAULT false,
      parent_sign_hash bytea,
      owner_timestamp bigint NOT NULL,
      sign_b64 bytea NOT NULL,
      PRIMARY KEY (user_hash, uuid, sign_hash)
    )
    """, """
    DROP TABLE user_storage_versions
    """

    # Index on parent_sign_hash for version chain traversal
    create index(:user_storage_versions, [:parent_sign_hash])

    # Add versioning fields to user_storage table
    alter table(:user_storage) do
      add :deleted_flag, :boolean, null: false, default: false
      add :parent_sign_hash, :binary, null: true
      add :owner_timestamp, :bigint, null: false, default: 0
      add :sign_b64, :binary, null: false, default: <<>>
      add :sign_hash, :binary, null: false, default: <<>>
    end

    # Add foreign key constraint: parent_sign_hash must exist in user_storage_versions
    # Note: This is a composite FK referencing (user_hash, uuid, sign_hash)
    execute """
    ALTER TABLE user_storage
    ADD CONSTRAINT user_storage_parent_sign_hash_fkey
    FOREIGN KEY (user_hash, uuid, parent_sign_hash)
    REFERENCES user_storage_versions(user_hash, uuid, sign_hash)
    ON DELETE RESTRICT
    """, """
    ALTER TABLE user_storage
    DROP CONSTRAINT user_storage_parent_sign_hash_fkey
    """
  end
end
