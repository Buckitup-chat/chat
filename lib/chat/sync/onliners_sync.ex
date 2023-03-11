defmodule Chat.Sync.OnlinersSync do
  @moduledoc """
  Waits for onliners sync messages from platform.
  After receiving a "get_keys" message, it gathers online users' keys
  and sends them back to platform.
  """

  use GenServer

  alias ChatWeb.Presence
  alias Phoenix.PubSub

  @incoming_topic "platform_onliners->chat_onliners"
  @outgoing_topic "chat_onliners->platform_onliners"
  @presence_topic "onliners_sync"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)
    {:ok, nil}
  end

  def handle_info("get_keys", state) do
    keys =
      @presence_topic
      |> Presence.list()
      |> Enum.reduce(MapSet.new(), fn {_key, %{metas: metas}}, keys ->
        metas
        |> List.first()
        |> Map.get(:keys)
        |> MapSet.union(keys)
      end)

    PubSub.broadcast(Chat.PubSub, @outgoing_topic, {:user_keys, keys})

    {:noreply, state}
  end
end
