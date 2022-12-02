defmodule Chat.Db.Switching do
  @moduledoc """
  Write flow switching
  """

  alias Chat.Db.Common
  alias Chat.Db.WriteQueue

  def mirror(from, to) do
    from_pipe = Common.names(from)
    to_pipe = Common.names(to)

    WriteQueue.set_mirror(from_pipe.queue, to_pipe.writer)
    WriteQueue.set_mirror(to_pipe.queue, nil)
  end

  def set_default(name) do
    %{queue: queue_name, status: status_relay_name} = Common.names(name)
    Common.put_chat_db_env(:data_queue, queue_name)
    Common.put_chat_db_env(:data_pid, name)
    Common.put_chat_db_env(:data_dry, status_relay_name)

    Chat.Ordering.reset()
  end
end
