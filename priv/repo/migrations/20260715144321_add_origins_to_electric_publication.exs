defmodule Chat.Repo.Migrations.AddOriginsToElectricPublication do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE origins;
    EXCEPTION
      WHEN duplicate_object THEN NULL;
    END $$;
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default DROP TABLE origins;
    EXCEPTION
      WHEN undefined_object THEN NULL;
    END $$;
    """
  end
end
