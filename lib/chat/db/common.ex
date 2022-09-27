defmodule Chat.Db.Common do
  @moduledoc "DB helper functions"

  alias Chat.Db.Queries
  alias Chat.Db.WritableUpdater

  @app_atom :chat
  @checking_writable_timeout 500

  def writable_action(action) do
    case get_chat_db_env(:writable) do
      :yes ->
        action.()

      :checking ->
        Process.sleep(@checking_writable_timeout)

        if :yes == get_chat_db_env(:writable) do
          action.()
        end
    end
  end

  def budgeted_put(db, key, value) do
    budget = calc_budget(key, value)
    current_budget = get_chat_db_env(:write_budget)

    put_chat_db_env(:write_budget, max(0, current_budget - budget))

    if budget > current_budget do
      put_chat_db_env(:writable, :checking)
      WritableUpdater.check()
    end

    Queries.put(db, key, value)
  end

  def calc_budget(key, value) do
    case key do
      {:action_log, _, _} -> 100 + 300
      {:memo, _} -> 100 + String.length(value)
      {:users, _} -> 200 + 4_000
      {:file, _} -> 2000
      {:file_chunk, _, first, last} -> 200 + trunc((last - first + 1) * 1.2)
      {:dialogs, _} -> 200 + 2 * 2_200
      {:dialog_message, _, _, _} -> 300 + 2 * 1_700
      _ -> 11_000_000
    end
  end

  def get_chat_db_env(key) do
    Application.fetch_env!(@app_atom, key)
  end

  def put_chat_db_env(key, value) do
    Application.put_env(@app_atom, key, value)
  end
end
