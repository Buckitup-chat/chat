defmodule Chat.Repo.Migrations.FileChunksResetAutovacuum do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE file_chunks RESET (
      autovacuum_vacuum_scale_factor,
      autovacuum_analyze_scale_factor,
      autovacuum_vacuum_cost_delay
    )
    """
  end

  def down do
    execute """
    ALTER TABLE file_chunks SET (
      autovacuum_vacuum_scale_factor = 0.01,
      autovacuum_analyze_scale_factor = 0.02,
      autovacuum_vacuum_cost_delay = 40
    )
    """
  end
end
