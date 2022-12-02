defmodule Chat.Db.Common do
  @moduledoc "DB helper functions"

  @app_atom :chat

  def names(name),
    do: %{
      queue: :"#{name}.WriteQueue",
      status: :"#{name}.DryStatus",
      writer: :"#{name}.QueueWriter"
    }

  def db_state(name) do
    names(name)
    |> Map.new(fn {name, registered_name} ->
      with pid <- Process.whereis(registered_name),
           false <- is_nil(pid),
           state <- :sys.get_state(pid) do
        {name, state}
      else
        _ ->
          {name, registered_name}
      end
    end)
  end

  def is_dry?, do: Application.fetch_env!(@app_atom, :data_dry) |> is_dry?()

  def is_dry?(relay) do
    Agent.get(relay, & &1)
  end

  def get_chat_db_env(key) do
    Application.fetch_env!(@app_atom, key)
  end

  def put_chat_db_env(key, value) do
    Application.put_env(@app_atom, key, value)
  end
end
