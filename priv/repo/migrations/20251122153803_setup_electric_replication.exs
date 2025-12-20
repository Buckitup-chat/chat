defmodule Chat.Repo.Migrations.SetupElectricReplication do
  use Ecto.Migration

  def up do
    # Create the publication for Electric if it doesn't exist
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'electric_publication_default') THEN
        CREATE PUBLICATION electric_publication_default FOR TABLE users;
      ELSE
        -- If publication exists, ensure users table is included
        ALTER PUBLICATION electric_publication_default ADD TABLE users;
      END IF;
    EXCEPTION
      WHEN duplicate_object THEN
        -- Table already in publication, ignore
        NULL;
    END $$;
    """

    # Note: Replication slots cannot be created in a transaction that has performed writes
    # The slot should be created manually or via a separate script:
    # psql -U postgres -d chat -c "SELECT pg_create_logical_replication_slot('electric_slot_default', 'pgoutput');"
    # This migration just verifies it exists
    execute """
    DO $$
    DECLARE
      slot_exists boolean;
    BEGIN
      SELECT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'electric_slot_default') INTO slot_exists;
      IF NOT slot_exists THEN
        RAISE NOTICE 'Replication slot electric_slot_default does not exist. It should be created manually.';
        RAISE NOTICE 'Run: psql -U postgres -d chat -c "SELECT pg_create_logical_replication_slot(''electric_slot_default'', ''pgoutput'');"';
      END IF;
    END $$;
    """
  end

  def down do
    # Drop the replication slot if it exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'electric_slot_default') THEN
        PERFORM pg_drop_replication_slot('electric_slot_default');
      END IF;
    END $$;
    """

    # Drop the publication
    execute """
    DROP PUBLICATION IF EXISTS electric_publication_default;
    """
  end
end
