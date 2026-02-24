defmodule Chat.Repo.Migrations.DropTimestampsFromUserStorage do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE user_storage
    DROP COLUMN IF EXISTS inserted_at,
    DROP COLUMN IF EXISTS updated_at;
    """
  end

  def down do
    # Timestamps were never part of the original schema, so no need to re-add them
    :ok
  end
end
