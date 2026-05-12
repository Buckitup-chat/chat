defmodule Chat.Repo.Migrations.AddFilesAndFileChunksToElectricPublication do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE files;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE file_chunks;
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
    END $$;
    """
  end

  def down do
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE files"
    execute "ALTER PUBLICATION electric_publication_default DROP TABLE file_chunks"
  end
end
