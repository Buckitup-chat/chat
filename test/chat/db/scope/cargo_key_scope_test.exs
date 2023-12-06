defmodule Chat.Db.Scope.CargoKeyScopeTest do
  use ExUnit.Case, async: false

  alias Chat.AdminRoom
  alias Chat.Db.Scope.KeyScope
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.User

  test "room and invitations in dialogs should be selected" do
    {bot_key, room_key} = generate_user_with_dialogs_content_and_invite_in_room()
    assert_keys_for_cargo_keys(room_key, [bot_key])
  end

  test "room invitation should be found in dialog of checkpoint and cargo user by only checkpoints key" do
    {admin, john} = {User.login("admin"), User.login("John")}

    {[checkpoint1_key, checkpoint2_key], cargo_user} =
      generate_checkpoints_and_cargo_user([admin, john])

    {_dialog, room_key} = generate_dialogs_and_cargo_room_invite([admin, john], cargo_user)
    assert_keys_for_cargo_keys(room_key, [checkpoint1_key, checkpoint2_key])
  end

  defp assert_keys_for_cargo_keys(room_key, checkpoint_keys) do
    Process.sleep(100)
    keys = KeyScope.get_cargo_keys(Chat.Db.db(), room_key, checkpoint_keys)

    expected_keys = %{
      dialog_message: 1,
      dialogs: 1,
      room_invite: 1,
      room_invite_index: 1,
      rooms: 1
    }

    assert expected_keys == filter_and_count_keys(keys)
  end

  defp filter_and_count_keys(keys) do
    keys
    |> MapSet.to_list()
    |> Enum.frequencies_by(&elem(&1, 0))
    |> Map.drop([:users])
  end

  defp generate_checkpoints_and_cargo_user(identities) do
    data =
      Enum.reduce(identities, %{keys: [], cards: []}, fn identity, acc ->
        register_and_put_user(identity)
        card = Chat.Card.from_identity(identity)

        %{
          keys: [Identity.pub_key(identity) | acc.keys],
          cards: [card | acc.cards]
        }
      end)

    store_cargo_settings_checkpoints(data.cards)
    :ok = "Cargoman" |> Identity.create() |> AdminRoom.store_cargo_user()
    AdminRoom.get_cargo_settings()
    {data.keys, AdminRoom.get_cargo_user()}
  end

  defp store_cargo_settings_checkpoints(cards) do
    :ok =
      AdminRoom.store_cargo_settings(%{
        AdminRoom.get_cargo_settings()
        | checkpoints: cards
      })
  end

  defp register_and_put_user(identity) do
    identity |> tap(&User.register/1) |> tap(&User.UsersBroker.put/1)
  end

  defp generate_dialogs_and_cargo_room_invite([checkpoint1, _checkpoint2], cargo_user) do
    {room_identity, _room} = Rooms.add(checkpoint1, "New Cargo room", :cargo)
    room_key = Identity.pub_key(room_identity)

    dialog =
      Dialogs.find_or_open(
        checkpoint1,
        cargo_user |> Chat.Card.from_identity()
      )

    create_and_add_room_invite(room_identity, dialog, checkpoint1)

    {dialog, room_key}
  end

  defp create_and_add_room_invite(room_identity, dialog, checkpoint) do
    room_identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(checkpoint, dialog)
    |> RoomInviteIndex.add(dialog, checkpoint)
  end

  defp generate_user_with_dialogs_content_and_invite_in_room do
    user = User.login("Alice")
    register_and_put_user(user)

    bot = User.login("Bob")
    register_and_put_user(bot)
    bot_key = Identity.pub_key(bot)

    {room_identity, _room} = Rooms.add(user, "Room")
    room_key = Identity.pub_key(room_identity)

    dialog = Dialogs.find_or_open(user, bot |> Chat.Card.from_identity())

    "hi"
    |> Messages.Text.new(DateTime.utc_now())
    |> Dialogs.add_new_message(user, dialog)

    create_and_add_room_invite(room_identity, dialog, user)

    {bot_key, room_key}
  end
end
