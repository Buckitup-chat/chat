defmodule Chat.Repo.Migrations.AddSourceDriveIdToMissingChunks do
  use Ecto.Migration

  def change do
    alter table(:missing_chunks) do
      add :source_drive_id, :text
    end

    execute(
      "ALTER TABLE missing_chunks ALTER COLUMN peer_url DROP NOT NULL",
      "ALTER TABLE missing_chunks ALTER COLUMN peer_url SET NOT NULL"
    )

    create index(:missing_chunks, [:peer_url],
      where: "data_hash IS NOT NULL AND peer_url IS NOT NULL",
      name: :missing_chunks_peer_url_fetchable_idx
    )

    create index(:missing_chunks, [:source_drive_id],
      where: "data_hash IS NOT NULL AND source_drive_id IS NOT NULL",
      name: :missing_chunks_source_drive_id_fetchable_idx
    )

    create index(:missing_chunks, [:attempts, :updated_at], where: "data_hash IS NOT NULL")
  end
end
