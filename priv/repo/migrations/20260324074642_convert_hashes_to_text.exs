defmodule Chat.Repo.Migrations.ConvertHashesToText do
  use Ecto.Migration

  def up do
    # Step 1: Drop all foreign key constraints
    execute "ALTER TABLE user_storage DROP CONSTRAINT user_storage_user_hash_fkey"
    execute "ALTER TABLE user_storage_versions DROP CONSTRAINT user_storage_versions_user_hash_fkey"
    execute "ALTER TABLE user_storage DROP CONSTRAINT user_storage_parent_sign_hash_fkey"

    # Step 2: Convert all columns to text
    execute "ALTER TABLE user_cards ALTER COLUMN user_hash TYPE text"
    execute "ALTER TABLE user_storage ALTER COLUMN user_hash TYPE text"
    execute "ALTER TABLE user_storage_versions ALTER COLUMN user_hash TYPE text"
    execute "ALTER TABLE user_storage ALTER COLUMN sign_hash TYPE text"
    execute "ALTER TABLE user_storage ALTER COLUMN parent_sign_hash TYPE text"
    execute "ALTER TABLE user_storage_versions ALTER COLUMN sign_hash TYPE text"
    execute "ALTER TABLE user_storage_versions ALTER COLUMN parent_sign_hash TYPE text"

    # Step 3: Drop the user_hash domain
    execute "DROP DOMAIN user_hash"

    # Step 4: DELETE all existing data (no migration possible)
    execute "DELETE FROM user_storage_versions"
    execute "DELETE FROM user_storage"
    execute "DELETE FROM user_cards"

    # Step 5: Recreate foreign key constraints
    execute """
    ALTER TABLE user_storage
    ADD CONSTRAINT user_storage_user_hash_fkey
    FOREIGN KEY (user_hash)
    REFERENCES user_cards(user_hash)
    ON DELETE CASCADE
    """

    execute """
    ALTER TABLE user_storage_versions
    ADD CONSTRAINT user_storage_versions_user_hash_fkey
    FOREIGN KEY (user_hash)
    REFERENCES user_cards(user_hash)
    ON DELETE CASCADE
    """

    execute """
    ALTER TABLE user_storage
    ADD CONSTRAINT user_storage_parent_sign_hash_fkey
    FOREIGN KEY (user_hash, uuid, parent_sign_hash)
    REFERENCES user_storage_versions(user_hash, uuid, sign_hash)
    ON DELETE RESTRICT
    """

    # Step 6: Add validation constraints
    execute """
    ALTER TABLE user_cards
    ADD CONSTRAINT user_hash_format_check
    CHECK (user_hash ~ '^u_[a-f0-9]{128}$')
    """

    execute """
    ALTER TABLE user_storage
    ADD CONSTRAINT sign_hash_format_check
    CHECK (sign_hash ~ '^uss_[a-f0-9]{128}$')
    """

    execute """
    ALTER TABLE user_storage_versions
    ADD CONSTRAINT sign_hash_format_check
    CHECK (sign_hash ~ '^uss_[a-f0-9]{128}$')
    """
  end

  def down do
    raise "No rollback - this is a one-way migration for PoC stage"
  end
end
