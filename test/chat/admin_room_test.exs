defmodule Chat.AdminRoomTest do
  use ExUnit.Case, async: false

  alias Chat.Admin.MediaSettings

  alias Chat.{
    AdminDb,
    AdminRoom,
    Card,
    Dialogs,
    Identity,
    RoomInvites,
    User,
    Utils
  }

  alias Chat.Messages

  setup do
    AdminDb.db() |> CubDB.clear()
  end

  test "should be created on first user login or create", do: :todo_in_lobby_test?

  test "should not create more than one" do
    admin_with_room("Alice")

    assert_raise RuntimeError, fn ->
      AdminRoom.create()
    end
  end

  test "new admins should be added through invite" do
    {alice, admin_room_identity} = admin_with_room("Alice")
    {bob, bob_card, _} = make_user("Bob")

    dialog = Dialogs.find_or_open(alice, bob_card)

    admin_room_identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_message] = dialog |> Dialogs.read(bob)
    assert :room_invite == bob_message.type

    bob_room_identity =
      bob_message.content
      |> Utils.StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    assert bob_room_identity == admin_room_identity
  end

  test "admin list should contain admins that visited at least once" do
    {alice, _admin_room_identity} = admin_with_room("Alice")
    alice_card = Card.from_identity(alice)

    assert [] = AdminRoom.admin_list()

    AdminRoom.visit(alice)

    assert [^alice_card] = AdminRoom.admin_list()
  end

  test "Admin should be able to store and read wifi password set" do
    {_alice, admin_room_identity} = admin_with_room("Alice")

    password = "secret"

    AdminRoom.store_wifi_password(password)
    assert password != AdminDb.get(:wifi_password)

    assert password == AdminRoom.get_wifi_password(admin_room_identity)
  end

  test "admin should be able to read and store media settings" do
    admin_with_room("Alice")

    assert %MediaSettings{} = media_settings = AdminRoom.get_media_settings()
    assert media_settings.functionality == :backup

    media_settings = %MediaSettings{functionality: :onliners}
    AdminRoom.store_media_settings(media_settings)

    assert %MediaSettings{} = media_settings = AdminRoom.get_media_settings()
    assert media_settings.functionality == :onliners
  end

  defp admin_with_room(name) do
    if AdminRoom.created?() do
      raise "Admihn room is already created"
    end

    admin_room_identity = AdminRoom.create()
    {admin_identity, _, _} = make_user(name)

    {admin_identity, admin_room_identity}
  end

  defp make_user(name) do
    identity = User.login(name)
    hash = User.register(identity)
    card = Card.from_identity(identity)

    {identity, card, hash}
  end
end
