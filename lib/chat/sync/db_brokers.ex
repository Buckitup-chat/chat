defmodule Chat.Sync.DbBrokers do
  @moduledoc "Db brokers handlers"
  alias Chat.Rooms.RoomsBroker
  alias Chat.User.UsersBroker

  alias Phoenix.PubSub

  @lobby_topic "chat::lobby"
  @admin_topic "chat::admin"

  def refresh do
    :ok = RoomsBroker.sync()
    :ok = UsersBroker.sync()

    broadcast_refresh()
  catch
    _, _  ->
      Task.start(fn ->
        5
        |> :timer.seconds()
        |> Process.sleep()

        Chat.Sync.DbBrokers.refresh()
      end)
  end

  def broadcast_refresh do
    :ok = PubSub.broadcast(Chat.PubSub, @lobby_topic, {:lobby, :refresh_rooms_and_users})
    :ok = PubSub.broadcast(Chat.PubSub, @admin_topic, {:admin, :refresh_rooms_and_users})
  end
end
