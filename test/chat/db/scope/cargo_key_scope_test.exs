defmodule Chat.Db.Scope.CargoKeyScopeTest do
  use ExUnit.Case, async: false

  alias Chat.{
    AdminRoom,
    Db.Scope.KeyScope,
    Dialogs,
    Identity,
    Messages,
    RoomInviteIndex,
    Rooms,
    User,
    Utils
  }

  @timeout 100

  setup do
    {bot_key, room_key} = generate_user_with_dialogs_content_and_invite_in_room()
    {:ok, %{bot_key: bot_key, room_key: room_key}}
  end

  test "room and invitations in dialogs should be selected", %{
    bot_key: bot_key,
    room_key: room_key
  } do
    assert_keys_for_cargo_keys(room_key, [bot_key], 1)
  end

  test "room invitation should be found in dialog of operator and user by only checkpoints key" do
    {[checkpoints, checkpoint_keys], operators, users} = setup_test_data(2, 1, 2)
    assert Enum.count(checkpoints) == 2

    operator = List.first(operators)
    room_identity = generate_cargo_room(operator)
    room_key = Identity.pub_key(room_identity)

    generate_dialogs_and_cargo_room_invite(checkpoints, operator, room_identity)
    user_c = List.first(users)
    generate_dialogs_and_cargo_room_invite([user_c], operator, room_identity)

    user_d = List.last(users)
    generate_dialogs_and_cargo_room_invite([user_d], user_c, room_identity)

    assert_keys_for_cargo_keys(room_key, checkpoint_keys, 4)
  end

  test "room invitations found up to 1 handshake" do
    {[checkpoints, checkpoint_keys], operators, users} = setup_test_data(3, 2, 4)
    assert Enum.count(checkpoints) == 3

    operator_1 = Enum.at(operators, 0)
    operator_2 = Enum.at(operators, 1)
    room_identity = generate_cargo_room(operator_1)
    room_key = Identity.pub_key(room_identity)

    generate_dialogs_and_cargo_room_invite(
      [Enum.at(checkpoints, 0), Enum.at(checkpoints, 1)],
      operator_1,
      room_identity
    )

    generate_dialogs_and_cargo_room_invite([Enum.at(checkpoints, 2)], operator_2, room_identity)

    generate_dialogs_and_cargo_room_invite([Enum.at(users, 0)], operator_1, room_identity)

    generate_dialogs_and_cargo_room_invite(
      [Enum.at(users, 1), Enum.at(users, 3)],
      Enum.at(users, 0),
      room_identity
    )

    first_handshake_indexed_messages =
      generate_dialogs_and_cargo_room_invite(
        [Enum.at(users, 2)],
        Enum.at(users, 1),
        room_identity
      )

    second_handshake_indexed_messages =
      generate_dialogs_and_cargo_room_invite(
        [Enum.at(users, 3), Enum.at(users, 0)],
        Enum.at(users, 2),
        room_identity
      )

    cargo_keys =
      KeyScope.get_cargo_keys(Chat.Db.db(), room_key, checkpoint_keys)
      |> Enum.map(fn entry ->
        case entry do
          {:room_invite_index, _reader_hash, invite_key} ->
            invite_key

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    assert first_handshake_indexed_messages
           |> Enum.any?(&MapSet.member?(cargo_keys, &1))

    refute second_handshake_indexed_messages
           |> Enum.any?(&MapSet.member?(cargo_keys, &1))
  end

  defp setup_test_data(checkpoints_count, operators_count, users_count) do
    checkpoints = Enum.map(1..checkpoints_count, &("checkpoint#{&1}" |> User.login()))
    checkpoint_keys = generate_checkpoints(checkpoints)

    operators =
      Enum.map(
        1..operators_count,
        &("operator#{&1}" |> User.login() |> create_user_from_identity())
      )

    users =
      Enum.map(1..users_count, &("user#{&1}" |> User.login() |> create_user_from_identity()))

    {[checkpoints, checkpoint_keys], operators, users}
  end

  defp assert_keys_for_cargo_keys(room_key, checkpoint_keys, expected_count) do
    Process.sleep(@timeout)

    keys =
      KeyScope.get_cargo_keys(Chat.Db.db(), room_key, checkpoint_keys)

    expected_keys = %{
      dialog_message: expected_count,
      dialogs: expected_count,
      room_invite: expected_count,
      room_invite_index: expected_count,
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

  defp generate_checkpoints(identities) do
    data =
      Enum.reduce(identities, %{keys: [], cards: []}, fn identity, acc ->
        create_user_from_identity(identity)
        card = Chat.Card.from_identity(identity)

        %{
          keys: [Identity.pub_key(identity) | acc.keys],
          cards: [card | acc.cards]
        }
      end)

    store_cargo_settings_checkpoints(data.cards)
    data.keys
  end

  defp store_cargo_settings_checkpoints(cards) do
    :ok = AdminRoom.store_cargo_settings(%{AdminRoom.get_cargo_settings() | checkpoints: cards})
  end

  defp create_user_from_identity(identity) do
    identity |> tap(&User.register/1) |> tap(&User.UsersBroker.put/1)
  end

  defp generate_cargo_room(user) do
    {room_identity, _room} = Rooms.add(user, "Cargo room", :cargo)
    room_identity
  end

  defp generate_dialogs_and_cargo_room_invite(checkpoints, user, room_identity) do
    for checkpoint <- checkpoints,
        into: [],
        do:
          user
          |> Dialogs.find_or_open(checkpoint |> Chat.Card.from_identity())
          |> create_and_add_room_invite(room_identity, user)
  end

  defp create_and_add_room_invite(dialog, room_identity, user) do
    room_invitation_message =
      room_identity
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(user, dialog)
      |> RoomInviteIndex.add(dialog, user)

    Dialogs.read_message(dialog, room_invitation_message, user)
    |> Map.fetch!(:content)
    |> Utils.StorageId.from_json_to_key()
  end

  defp generate_user_with_dialogs_content_and_invite_in_room do
    user = User.login("Alice")
    create_user_from_identity(user)

    bot = User.login("Bob")
    create_user_from_identity(bot)
    bot_key = Identity.pub_key(bot)

    {room_identity, _room} = Rooms.add(user, "Room")
    room_key = Identity.pub_key(room_identity)

    dialog = Dialogs.find_or_open(user, bot |> Chat.Card.from_identity())

    "hi"
    |> Messages.Text.new(DateTime.utc_now())
    |> Dialogs.add_new_message(user, dialog)

    create_and_add_room_invite(dialog, room_identity, user)

    {bot_key, room_key}
  end
end
