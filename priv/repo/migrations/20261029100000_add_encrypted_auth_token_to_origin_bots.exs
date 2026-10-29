defmodule Chat.Repo.Migrations.AddEncryptedAuthTokenToOriginBots do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE origin_bots ADD COLUMN encrypted_auth_token_b64 BYTEA")

    execute("ALTER TABLE origin_bots ALTER COLUMN encrypted_auth_token_b64 SET STORAGE EXTERNAL")
  end

  def down do
    execute("ALTER TABLE origin_bots DROP COLUMN encrypted_auth_token_b64")
  end
end
