defmodule Chat.Db.WriteQueue.FileSkipSet do
  @moduledoc "ETS table wrapper to keep list of skipped files"

  def new(), do: :ets.new(nil, [:public])

  def delete(ref) do
    :ets.delete(ref)
  rescue
    _ -> true
  end

  def add_skipped_file(ref, key) do
    :ets.insert(ref, {key})
  rescue
    _ -> false
  end

  def member?(ref, key) do
    :ets.member(ref, key)
  rescue
    _ -> false
  end
end
