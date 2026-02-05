defmodule Chat.Repo.Migrations.CreateUserHashDomain do
  use Ecto.Migration

  def up do
    # Create the user_hash domain type
    # prefix 0x01 = \x01 in bytea hex format
    execute "CREATE DOMAIN user_hash AS bytea CHECK (substring(VALUE from 1 for 1) = '\\x01'::bytea)"
  end

  def down do
    execute "DROP DOMAIN user_hash"
  end
end
