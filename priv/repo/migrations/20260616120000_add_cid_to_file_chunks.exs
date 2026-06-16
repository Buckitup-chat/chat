defmodule Chat.Repo.Migrations.AddCidToFileChunks do
  use Ecto.Migration

  def up do
    alter table(:file_chunks) do
      add :cid, :text
    end
  end

  def down do
    alter table(:file_chunks) do
      remove :cid
    end
  end
end
