defmodule Chat.Repo.Migrations.DropTimestampsFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :inserted_at
      remove :updated_at
    end
  end
end