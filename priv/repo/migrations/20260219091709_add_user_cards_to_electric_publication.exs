defmodule Chat.Repo.Migrations.AddUserCardsToElectricPublication do
  @moduledoc """
  Adds the user_cards table to the Electric publication for real-time sync.

  This enables Electric (PostgreSQL logical replication) to stream changes from the
  user_cards table to connected LiveView clients. The migration handles the case
  where the table is already in the publication gracefully.
  """
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      ALTER PUBLICATION electric_publication_default ADD TABLE user_cards;
    EXCEPTION
      WHEN duplicate_object THEN
        -- Table already in publication, ignore
        NULL;
    END $$;
    """
  end

  def down do
    execute """
    ALTER PUBLICATION electric_publication_default DROP TABLE user_cards;
    """
  end
end
