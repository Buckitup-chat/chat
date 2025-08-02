defmodule Chat.Repo.Migrations.FixUsersTable do
  use Ecto.Migration

  def change do
    # Change name column to text type to allow longer names
    alter table(:users) do
      modify :name, :text
    end

    # Check if hash column exists and remove it if it does
    # The hash is a virtual field in the schema, not a database column
    execute "ALTER TABLE users DROP COLUMN IF EXISTS hash"
  end
end
