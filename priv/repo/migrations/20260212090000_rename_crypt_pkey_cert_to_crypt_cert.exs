defmodule Chat.Repo.Migrations.RenameCryptPkeyCertToCryptCert do
  use Ecto.Migration

  def change do
    rename table(:user_cards), :crypt_pkey_cert, to: :crypt_cert
  end
end
