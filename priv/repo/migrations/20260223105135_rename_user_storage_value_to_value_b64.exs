defmodule Chat.Repo.Migrations.RenameUserStorageValueToValueB64 do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_storage' AND column_name = 'value'
      ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_storage' AND column_name = 'value_b64'
      ) THEN
        ALTER TABLE user_storage RENAME COLUMN value TO value_b64;
      END IF;
    END $$;
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_storage' AND column_name = 'value_b64'
      ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_storage' AND column_name = 'value'
      ) THEN
        ALTER TABLE user_storage RENAME COLUMN value_b64 TO value;
      END IF;
    END $$;
    """
  end
end
