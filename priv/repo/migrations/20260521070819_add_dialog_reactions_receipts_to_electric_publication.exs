defmodule Chat.Repo.Migrations.AddDialogReactionsReceiptsToElectricPublication do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE dialog_message_reactions;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE dialog_message_receipts;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """
  end

  def down do
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE dialog_message_receipts"
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE dialog_message_reactions"
  end
end
