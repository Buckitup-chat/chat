defmodule Chat.Sync.OnlinersSyncTest do
  use ExUnit.Case, async: false

  alias Chat.Sync.OnlinersSync
  alias ChatWeb.OnlinersPresence
  alias Phoenix.PubSub

  @outgoing_topic "chat_onliners->platform_onliners"

  test "replies with the keys of all online users" do
    PubSub.subscribe(Chat.PubSub, @outgoing_topic)
    {:ok, sync} = GenServer.start_link(OnlinersSync, :ok)

    track_user("onliner_a", ["key_a1", "key_a2"])
    track_user("onliner_b", ["key_b"])

    send(sync, "get_online_users_keys")

    assert_receive {:user_keys, keys}
    assert MapSet.subset?(MapSet.new(["key_a1", "key_a2", "key_b"]), keys)
  end

  # Helpers

  defp track_user(presence_key, keys) do
    test_pid = self()

    spawn_link(fn ->
      {:ok, _} = OnlinersPresence.track(self(), presence_key, MapSet.new(keys))
      send(test_pid, :tracked)
      Process.sleep(:infinity)
    end)

    assert_receive :tracked
  end
end
