defmodule Chat.Repo.Migrations.AddDialogMessagesToElectricPublication do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE dialog_messages;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE dialog_messages_versions;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """
  end

  def down do
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE dialog_messages_versions"
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE dialog_messages"
  end
end
