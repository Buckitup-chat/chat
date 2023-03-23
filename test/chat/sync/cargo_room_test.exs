defmodule Chat.Sync.CargoRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Sync.CargoRoom

  describe "get/1" do
    test "returns room pub key" do
      key = :rand.uniform()
      :sys.replace_state(CargoRoom, fn _state -> key end)
      assert CargoRoom.get() == key
    end
  end

  describe "set/1" do
    test "sets cargo room pub key" do
      key = :rand.uniform()
      CargoRoom.set(key)
      assert :sys.get_state(CargoRoom) == key
    end
  end
end
