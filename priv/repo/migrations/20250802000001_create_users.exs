defmodule Chat.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :pub_key, :binary, null: false
      add :hash, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:pub_key])
    create unique_index(:users, [:hash])
  end
end