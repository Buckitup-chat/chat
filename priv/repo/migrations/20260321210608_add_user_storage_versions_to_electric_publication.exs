defmodule Chat.Repo.Migrations.AddUserStorageVersionsToElectricPublication do
  @moduledoc """
  Adds the user_storage_versions table to the Electric publication for real-time sync.

  This enables Electric (PostgreSQL logical replication) to stream changes from the
  user_storage_versions table to connected clients. The migration handles the case where the
  table is already in the publication gracefully.
  """
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE user_storage_versions;
    EXCEPTION
      WHEN duplicate_object THEN
        -- Table already in publication, ignore
        NULL;
    END $$;
    """
  end

  def down do
    execute """
    ALTER PUBLICATION electric_publication_default DROP TABLE user_storage_versions;
    """
  end
end
