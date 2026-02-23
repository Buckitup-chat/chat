defmodule Chat.Repo.Migrations.RenameUserStorageValueToValueB64 do
  use Ecto.Migration

  def change do
    rename table(:user_storage), :value, to: :value_b64
  end
end
