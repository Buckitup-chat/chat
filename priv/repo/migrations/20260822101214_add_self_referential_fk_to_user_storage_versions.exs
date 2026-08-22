defmodule Chat.Repo.Migrations.AddSelfReferentialFkToUserStorageVersions do
  use Ecto.Migration

  def change do
    # Previously only indexed (see 20260321210327_add_versioning_to_user_storage.exs),
    # not FK-enforced. Not deferrable, matching user_storage_parent_sign_hash_fkey:
    # archiving always inserts one already-resolvable parent at a time, and a
    # deferred check would fire at COMMIT, bypassing Ecto's foreign_key_constraint
    # changeset mapping (and never firing at all inside the test sandbox, which
    # rolls back instead of committing).
    execute """
    ALTER TABLE user_storage_versions
    ADD CONSTRAINT user_storage_versions_parent_sign_hash_fkey
    FOREIGN KEY (user_hash, uuid, parent_sign_hash)
    REFERENCES user_storage_versions (user_hash, uuid, sign_hash)
    ON DELETE RESTRICT
    """, """
    ALTER TABLE user_storage_versions
    DROP CONSTRAINT user_storage_versions_parent_sign_hash_fkey
    """
  end
end
