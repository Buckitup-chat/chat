defmodule Chat.Repo.Migrations.AddContactFieldsToUserCards do
  use Ecto.Migration

  def change do
    alter table(:user_cards) do
      add :contact_pkey, :bytea
      add :contact_cert, :bytea
    end
  end
end
