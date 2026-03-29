defmodule Chat.Repo.Migrations.AddIntegrityFieldsToUserCards do
  use Ecto.Migration

  def change do
    alter table(:user_cards) do
      add :deleted_flag, :boolean, null: false, default: false
      add :owner_timestamp, :bigint, null: false
      add :sign_b64, :binary, null: false
    end
  end
end
