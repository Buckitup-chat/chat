defmodule Chat.Sync.DbBrokersTest do
  use ExUnit.Case, async: false

  import Rewire

  alias Chat.Sync.DbBrokers
  alias Phoenix.PubSub

  defmodule BrokerOk do
    def sync, do: :ok
  end

  defmodule BrokerDown do
    def sync, do: exit(:noproc)
  end

  defmodule NoSleep do
    def sleep(_ms), do: :ok
  end

  defmodule RefreshSpy do
    def refresh do
      [caller | _] = Process.get(:"$callers")
      send(caller, :refresh_retried)
    end
  end

  setup do
    PubSub.subscribe(Chat.PubSub, "chat::lobby")
    PubSub.subscribe(Chat.PubSub, "chat::admin")

    :ok
  end

  describe "refresh/0" do
    test "syncs both brokers and broadcasts refresh" do
      assert :ok = rewire(DbBrokers, RoomsBroker: BrokerOk, UsersBroker: BrokerOk).refresh()

      assert_receive {:lobby, :refresh_rooms_and_users}
      assert_receive {:admin, :refresh_rooms_and_users}
    end

    test "retries later when a broker is not available" do
      assert {:ok, _task} =
               rewire(DbBrokers,
                 RoomsBroker: BrokerDown,
                 UsersBroker: BrokerOk,
                 Process: NoSleep,
                 DbBrokers: RefreshSpy
               ).refresh()

      assert_receive :refresh_retried
      refute_received {:lobby, :refresh_rooms_and_users}
    end
  end

  describe "broadcast_refresh/0" do
    test "notifies lobby and admin" do
      assert :ok = DbBrokers.broadcast_refresh()

      assert_receive {:lobby, :refresh_rooms_and_users}
      assert_receive {:admin, :refresh_rooms_and_users}
    end
  end
end
