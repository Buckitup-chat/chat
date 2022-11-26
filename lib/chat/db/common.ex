defmodule Chat.Db.Common do
  @moduledoc "DB helper functions"

  alias Chat.Db.Queries
  alias Chat.Db.DbSyncWatcher
  # alias Chat.Db.WritableUpdater

  @app_atom :chat
  @checking_writable_timeout 500

  # todo: check if needed
  def writable_action(action) do
    case get_chat_db_env(:writable) do
      :yes ->
        action.()
        |> tap(fn _ -> DbSyncWatcher.mark() end)

      :checking ->
        Process.sleep(@checking_writable_timeout)

        if :yes == get_chat_db_env(:writable) do
          action.()
          |> tap(fn _ -> DbSyncWatcher.mark() end)
        end

      :no ->
        :ignored
    end
  end

  # todo: check if needed
  def budgeted_put(db, key, value) do
    # budget = calc_budget(key, value)
    # current_budget = get_chat_db_env(:write_budget)

    # put_chat_db_env(:write_budget, max(0, current_budget - budget))

    # if budget > current_budget do
    #   put_chat_db_env(:writable, :checking)
    #   WritableUpdater.check()
    # end

    if Process.alive?(db) do
      Queries.put(db, key, value)
    else
      put_chat_db_env(:writable, :no)
      Phoenix.PubSub.broadcast(Chat.PubSub, "chat->platform", :unmount_main)

      :ignored
    end
  end

  # todo: check if needed
  def calc_budget(key, value) do
    case key do
      {:action_log, _, _} -> 100 + 300
      {:memo, _} -> 100 + String.length(value)
      {:users, _} -> 200 + 4_000
      {:file, _} -> 2000
      {:file_chunk, _, first, last} -> 200 + trunc((last - first + 1) * 1.2)
      {:dialogs, _} -> 200 + 2 * 2_200
      {:dialog_message, _, _, _} -> 300 + 2 * 1_700
      {:room_invite, _} -> 200 + 4000
      {:rooms, _} -> 200 + 2_200
      {:room_message, _, _, _} -> 300 + 1_700
      _ -> 12_000_000
    end
  end

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
