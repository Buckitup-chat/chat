defmodule Chat.Db.InternalDbSupervisor do
  @moduledoc """
  Supervisor for internal DB
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    db_name = Chat.Db.InternalDb
    relay_name = Chat.Db.InternalDb.DryStatus
    queue_name = Chat.Db.InternalDb.WriteQueue
    writer_name = Chat.Db.InternalDb.QueueWriter

    children = [
      write_queue(queue_name),
      db(db_name, Chat.Db.file_path()),
      dry_status_relay(relay_name),
      writer(
        name: writer_name,
        db: db_name,
        queue: queue_name,
        status_relay: relay_name
      )
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp write_queue(name) do
    {Chat.Db.WriteQueue, name: name}
  end

  defp writer(opts) do
    {Chat.Db.QueueWriter.Process, opts}
  end

  defp dry_status_relay(name) do
    %{
      id: name,
      start: {Agent, :start_link, [fn -> false end, [name: name]]}
    }
  end

  defp db(name, path) do
    %{
      id: name,
      start:
        {CubDB, :start_link,
         [
           path,
           [
             auto_file_sync: false,
             auto_compact: false,
             name: name
           ]
         ]}
    }
  end
end
