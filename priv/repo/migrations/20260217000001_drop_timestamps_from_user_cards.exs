defmodule Chat.Repo.Migrations.DropTimestampsFromUserCards do
  use Ecto.Migration

  def change do
    alter table(:user_cards) do
      remove :inserted_at
      remove :updated_at
    end
  end
end
