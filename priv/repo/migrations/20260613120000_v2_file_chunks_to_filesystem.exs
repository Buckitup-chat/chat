defmodule Chat.Repo.Migrations.V2FileChunksToFilesystem do
  use Ecto.Migration

  def up do
    execute "TRUNCATE files, file_chunks, upload_chunks"

    alter table(:file_chunks) do
      remove :data_b64
      add :data_hash, :text, null: false, default: ""
    end

    execute "ALTER TABLE file_chunks ALTER COLUMN data_hash DROP DEFAULT"

    execute """
    ALTER TABLE file_chunks ADD CONSTRAINT file_chunks_data_hash_format
    CHECK (data_hash ~ '^fd_[a-f0-9]{128}$')
    """
  end

  def down do
    execute "ALTER TABLE file_chunks DROP CONSTRAINT IF EXISTS file_chunks_data_hash_format"

    execute "TRUNCATE files, file_chunks, upload_chunks"

    alter table(:file_chunks) do
      remove :data_hash
      add :data_b64, :binary, null: false, default: ""
    end

    execute "ALTER TABLE file_chunks ALTER COLUMN data_b64 DROP DEFAULT"
    execute "ALTER TABLE file_chunks ALTER COLUMN data_b64 SET STORAGE EXTERNAL"
  end
end
