defmodule Chat.Repo.Migrations.AddDialogKeysToElectricPublication do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE dialog_keys;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """
  end

  def down do
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE dialog_keys"
  end
end
