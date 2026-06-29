defmodule Chat.Repo.Migrations.CreateReplicaTriggers do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION notify_file_replicated() RETURNS trigger AS $$
    BEGIN
      PERFORM pg_notify('file_replicated',
        json_build_object('file_id', NEW.file_id, 'chunk_count', NEW.chunk_count)::text);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER file_replicated_trigger
      AFTER INSERT ON files FOR EACH ROW
      EXECUTE FUNCTION notify_file_replicated();
    """

    execute "ALTER TABLE files ENABLE REPLICA TRIGGER file_replicated_trigger;"

    execute """
    CREATE OR REPLACE FUNCTION notify_file_chunk_replicated() RETURNS trigger AS $$
    BEGIN
      PERFORM pg_notify('file_chunk_replicated',
        json_build_object('file_id', NEW.file_id, 'chunk_index', NEW.chunk_index,
                          'data_hash', NEW.data_hash, 'size', NEW.size)::text);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER file_chunk_replicated_trigger
      AFTER INSERT ON file_chunks FOR EACH ROW
      EXECUTE FUNCTION notify_file_chunk_replicated();
    """

    execute "ALTER TABLE file_chunks ENABLE REPLICA TRIGGER file_chunk_replicated_trigger;"
  end

  def down do
    execute "DROP TRIGGER IF EXISTS file_chunk_replicated_trigger ON file_chunks;"
    execute "DROP FUNCTION IF EXISTS notify_file_chunk_replicated();"
    execute "DROP TRIGGER IF EXISTS file_replicated_trigger ON files;"
    execute "DROP FUNCTION IF EXISTS notify_file_replicated();"
  end
end
