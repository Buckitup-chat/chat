defmodule Chat.Db.Switching do
  @moduledoc """
  Write flow switching
  """

  alias Chat.Db.Common
  alias Chat.Db.WriteQueue

  def mirror(from, to) when is_list(to) do
    from_queue = Common.names(from, :queue)
    to_queues = Enum.map(to, &Common.names(&1, :queue))
    to_writers = Enum.map(to, &Common.names(&1, :writer))

    WriteQueue.set_mirrors(to_writers, from_queue)
    WriteQueue.set_mirrors(nil, to_queues)
  end

  def mirror(from, to) do
    from_queue = Common.names(from, :queue)
    to_queue = Common.names(to, :queue)
    to_writer = Common.names(to, :writer)

    WriteQueue.set_mirrors([to_writer], from_queue)
    WriteQueue.set_mirrors(nil, to_queue)
  end

  def set_default(name) do
    queue_name = Common.names(name, :queue)
    status_relay_name = Common.names(name, :status)

    Common.put_chat_db_env(:data_queue, queue_name)
    Common.put_chat_db_env(:data_pid, name)
    Common.put_chat_db_env(:files_base_dir, CubDB.data_dir(name) <> "_files")
    Common.put_chat_db_env(:data_dry, status_relay_name)

    Chat.Ordering.reset()
  end
end
