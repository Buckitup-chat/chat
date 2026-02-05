defmodule Chat.Repo.Migrations.CreateUserCards do
  use Ecto.Migration

  def change do
    create table(:user_cards, primary_key: false) do
      add :user_hash, :user_hash, primary_key: true
      add :sign_pkey, :bytea, null: false
      add :crypt_pkey, :bytea, null: false
      add :crypt_pkey_cert, :bytea, null: false
      add :name, :text, null: false
    end
  end
end
