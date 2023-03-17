defmodule Chat.Db.Switching do
  @moduledoc """
  Write flow switching
  """

  alias Chat.Db.Common
  alias Chat.Db.WriteQueue

  def mirror(from, to) when is_list(to) do
    from_pipe = Common.names(from)
    to_pipe = Enum.map(to, &Common.names/1)
    to_pipe_queues = Enum.map(to_pipe, & &1.queue)
    to_pipe_writers = Enum.map(to_pipe, & &1.writer)

    WriteQueue.set_mirrors(to_pipe_writers, from_pipe.queue)
    WriteQueue.set_mirrors(nil, to_pipe_queues)
  end

  def mirror(from, to) do
    from_pipe = Common.names(from)
    to_pipe = Common.names(to)

    WriteQueue.set_mirrors([to_pipe.writer], from_pipe.queue)
    WriteQueue.set_mirrors(nil, to_pipe.queue)
  end

  def set_default(name) do
    %{queue: queue_name, status: status_relay_name} = Common.names(name)
    Common.put_chat_db_env(:data_queue, queue_name)
    Common.put_chat_db_env(:data_pid, name)
    Common.put_chat_db_env(:files_base_dir, CubDB.data_dir(name) <> "_files")
    Common.put_chat_db_env(:data_dry, status_relay_name)

    Chat.Ordering.reset()
  end
end
