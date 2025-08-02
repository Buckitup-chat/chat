defmodule Chat.Repo.Migrations.ChangeUsersPrimaryKey do
  use Ecto.Migration

  def up do
    # Drop the existing primary key constraint
    execute "ALTER TABLE users DROP CONSTRAINT users_pkey"
    
    # Remove the auto-generated ID column
    alter table(:users) do
      remove :id
    end
    
    # Add primary key constraint to pub_key
    execute "ALTER TABLE users ADD PRIMARY KEY (pub_key)"
  end

  def down do
    # Drop the primary key constraint on pub_key
    execute "ALTER TABLE users DROP CONSTRAINT users_pkey"
    
    # Add back the id column with serial type and make it the primary key
    alter table(:users) do
      add :id, :serial, primary_key: true
    end
  end
end
