defmodule Chat.Repo.Migrations.AddCidToMissingChunks do
  use Ecto.Migration

  def change do
    alter table(:missing_chunks) do
      add :cid, :text
    end

    create index(:missing_chunks, [:updated_at],
      name: :missing_chunks_bitswap_idx,
      where: "cid IS NOT NULL AND data_hash IS NOT NULL"
    )
  end
end
