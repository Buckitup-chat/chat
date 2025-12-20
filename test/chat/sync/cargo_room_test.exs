defmodule Chat.Sync.CargoRoomTest do
  use ChatWeb.DataCase, async: false

  alias Chat.AdminRoom
  alias Chat.Content.Files
  alias Chat.Db
  alias Chat.Db.ChangeTracker
  alias Chat.Db.Copying
  alias Chat.Rooms
  alias Chat.Sync.CargoRoom
  alias Chat.User
  alias Chat.Utils.StorageId

  describe "write_file/3" do
    test "saves image as a room message" do
      CargoRoom.remove()
      refute CargoRoom.get_room_key()

      operator = User.login("Operator")
      User.register(operator)

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

      assert :ignore = CargoRoom.write_file(cargo_bot, content, metadata, fn _ -> nil end)

      {room_identity, room} = Rooms.add(operator, "TestCargoRoom", :cargo)
      Rooms.await_saved(room_identity)
      CargoRoom.activate(room_identity.public_key)

      assert {:ok, _} =
               CargoRoom.write_file(cargo_bot, content, metadata, fn key ->
                 if key === room_identity.public_key, do: room_identity
               end)

      ChangeTracker.await()

      [%{type: :image, content: content}] = Rooms.read(room, room_identity)
      {id, secret} = content |> StorageId.from_json()
      [_, _, end_size, _, name, _] = Files.get(id, secret)

      assert end_size == to_string(size)
      assert "cargo_shot_" <> _ = name
      assert ".jpg" = Path.extname(name)
    end
  end

  describe "write_text" do
    test "text should be written into cargo room" do
      CargoRoom.remove()
      refute CargoRoom.get_room_key()

      operator = User.login("Operator")
      User.register(operator)

      cargo_bot = User.login("CargoBot2")
      AdminRoom.store_cargo_user(cargo_bot)
      cargo_bot_key = User.register(cargo_bot)
      User.await_saved(cargo_bot_key)

      content = "Cargo room message text"

      assert :ignore = CargoRoom.write_text(cargo_bot, content, fn _ -> nil end)

      {room_identity, room} = Rooms.add(operator, "TestCargoRoom2", :cargo)
      Rooms.await_saved(room_identity)
      CargoRoom.activate(room_identity.public_key)

      assert {:ok, db_keys} =
               CargoRoom.write_text(cargo_bot, content, fn key ->
                 if key === room_identity.public_key, do: room_identity
               end)

      Copying.await_written_into(db_keys, Db.db())

      [%{type: :text, content: read_content}] = Rooms.read(room, room_identity)

      assert read_content == content
    end
  end
end
