defmodule Chat.Sync.CargoRoomTest do
  use ExUnit.Case, async: false

  alias Chat.AdminRoom
  alias Chat.Content.Files
  alias Chat.Db.ChangeTracker
  alias Chat.Rooms
  alias Chat.Sync.CargoRoom
  alias Chat.User
  alias Chat.Utils.StorageId

  describe "write_file/3" do
    test "saves image as a room message" do
      CargoRoom.remove()
      refute CargoRoom.get_room_key()

      operator = User.login("Operator")
      operator_key = User.register(operator)
      User.await_saved(operator_key)

      cargo_bot = User.login("CargoBot")
      AdminRoom.store_cargo_user(cargo_bot)
      cargo_bot_key = User.register(cargo_bot)
      User.await_saved(cargo_bot_key)

      size = :rand.uniform(2 * 1024 * 2014)
      content = :crypto.strong_rand_bytes(size)

      metadata = %{
        "Content-Length" => "#{size}",
        "Content-Type" => "image/jpeg",
        "Name-Prefix" => "cargo_shot_"
      }

      assert :ignore = CargoRoom.write_file(cargo_bot, content, metadata)

      {room_identity, room} = Rooms.add(operator, "TestCargoRoom", :cargo)
      Rooms.await_saved(room_identity)
      CargoRoom.activate(room_identity.public_key)

      assert {:ok, _} = CargoRoom.write_file(cargo_bot, content, metadata)
      ChangeTracker.await()

      [%{type: :image, content: content}] = Rooms.read(room, room_identity)
      {id, secret} = content |> StorageId.from_json()
      [_, _, end_size, _, name, _] = Files.get(id, secret)

      assert end_size == to_string(size)
      assert "cargo_shot_" <> _ = name
      assert ".jpg" = Path.extname(name)
    end
  end
end
