defmodule ChatWeb.OnlinersPresence do
  @moduledoc """
  Tracks current user's keys for purpose of onliners sync.
  """

  alias ChatWeb.Presence

  @topic "onliners_sync"

  def track(pid, presence_key, user_keys) do
    Presence.track(pid, @topic, presence_key, %{keys: user_keys})
  end

  def update(pid, presence_key, user_keys) do
    Presence.update(pid, @topic, presence_key, %{keys: user_keys})
  end

  def untrack(pid, presence_key) do
    Presence.untrack(pid, @topic, presence_key)
  end
end
