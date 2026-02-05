defmodule Chat.Repo.Migrations.CreateUserStorage do
  use Ecto.Migration

  def change do
    create table(:user_storage, primary_key: false) do
      add :user_hash, references(:user_cards, column: :user_hash, type: :user_hash, on_delete: :delete_all), primary_key: true
      add :uuid, :uuid, primary_key: true
      add :value, :bytea, null: false
    end
  end
end
