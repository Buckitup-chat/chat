defmodule Chat.Rooms.RoomInputTest do
  use ChatWeb.DataCase, async: false

  alias Chat.Db.ChangeTracker
  alias Chat.Admin.MediaSettings
  alias Chat.Rooms.{Registry, Room, RoomInput}

  setup do
    Chat.Db.db()
    |> CubDB.clear()

    :ok
  end

  describe "changeset/2" do
    @valid_params %{
      name: "Room name",
      type: "public"
    }

    test "with valid params returns valid changeset" do
      Registry.update(%Room{name: "Room name", pub_key: "1234", type: :cargo})
      ChangeTracker.await({:rooms, "1234"})

      assert %Ecto.Changeset{} = changeset = RoomInput.changeset(%RoomInput{}, @valid_params)
      assert changeset.valid?
    end

    test "with missing or invalid name returns an error" do
      params = @valid_params |> Map.put(:name, nil)
      changeset = RoomInput.changeset(%RoomInput{}, params)
      assert_has_error(changeset, :name, "can't be blank")
    end

    test "with invalid type returns an error" do
      params = @valid_params |> Map.put(:type, "unknown")
      changeset = RoomInput.changeset(%RoomInput{}, params)
      assert_has_error(changeset, :type, "is invalid")
    end

    test "cargo type needs to be enabled" do
      media_settings = %MediaSettings{}
      params = @valid_params |> Map.put(:type, "cargo")
      changeset = RoomInput.changeset(%RoomInput{}, params, media_settings)
      assert_has_error(changeset, :type, "is invalid")

      media_settings = %MediaSettings{functionality: :cargo}
      params = @valid_params |> Map.put(:type, "cargo")

      assert %Ecto.Changeset{} =
               changeset = RoomInput.changeset(%RoomInput{}, params, media_settings)

      assert changeset.valid?
    end

    test "with duplicate room name for cargo type returns an error" do
      Registry.update(%Room{name: Map.get(@valid_params, :name), pub_key: "1234", type: :cargo})
      ChangeTracker.await({:rooms, "1234"})

      media_settings = %MediaSettings{functionality: :cargo}
      params = @valid_params |> Map.put(:type, "cargo")
      changeset = RoomInput.changeset(%RoomInput{}, params, media_settings)
      assert_has_error(changeset, :name, "has already been taken")
    end
  end
end
