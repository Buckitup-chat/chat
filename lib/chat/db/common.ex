defmodule Chat.Db.Common do
  @moduledoc "DB helper functions"

  @app_atom :chat

  def names(name),
    do: %{
      queue: names(name, :queue),
      status: names(name, :status),
      decider: names(name, :decider),
      read_supervisor: names(name, :read_supervisor),
      file_reader: names(name, :file_reader),
      write_supervisor: names(name, :write_supervisor),
      compactor: names(name, :compactor),
      writer: names(name, :writer)
    }

  def names(db_name, part), case(part) do
    :queue -> :"#{db_name}.Queue"
    :status -> :"#{db_name}.DryStatus"
    :decider -> :"#{db_name}.Decider"
    :read_supervisor -> :"#{db_name}.ReadSupervisor"
    :file_reader -> :"#{db_name}.FileReader"
    :write_supervisor -> :"#{db_name}.WriteSupervisor"
    :compactor -> :"#{db_name}.Compactor"
    :writer -> :"#{db_name}.Writer"
    _ -> nil
  end

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

  def dry?, do: Application.fetch_env!(@app_atom, :data_dry) |> dry?()

  def dry?(relay) do
    Agent.get(relay, & &1)
  end

  def get_chat_db_env(key) do
    Application.fetch_env!(@app_atom, key)
  end

  def put_chat_db_env(key, value) do
    Application.put_env(@app_atom, key, value)
  end
end
