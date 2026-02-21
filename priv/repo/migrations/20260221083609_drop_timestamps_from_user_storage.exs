defmodule Chat.Repo.Migrations.DropTimestampsFromUserStorage do
  use Ecto.Migration

  def change do
    alter table(:user_storage) do
      remove :inserted_at
      remove :updated_at
    end
  end
end
