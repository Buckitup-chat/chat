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
    {[checkpoints, checkpoint_keys], [operator], [user_c, user_d] = _users} =
      setup_test_data(2, 1, 2)

    assert Enum.count(checkpoints) == 2

    context =
      %{}
      |> generate_cargo_room(operator)
      |> put_dialogs_with_invites([checkpoints, operator], :index_1)
      |> put_dialogs_with_invites([[user_c], operator], :index_2)
      |> put_dialogs_with_invites([[user_d], user_c], :index_3)

    room_key = context |> Map.get(:room_identity) |> Identity.pub_key()

    assert_keys_for_cargo_keys(room_key, checkpoint_keys, 4)
  end

  test "room invitations found up to 1 handshake" do
    {
      [checkpoints, checkpoints_keys],
      [operator_1, operator_2],
      [user_1, user_2, user_3, user_4]
    } = setup_test_data(3, 2, 4)

    assert Enum.count(checkpoints) == 3

    invitations_board =
      %{}
      |> generate_cargo_room(operator_1)
      |> put_dialogs_with_invites([checkpoints, operator_1], :index_1)
      |> put_dialogs_with_invites([[Enum.at(checkpoints, 2)], operator_2], :index_2)
      |> put_dialogs_with_invites([[user_1], operator_1], :index_3)
      |> put_dialogs_with_invites([[user_2, user_4], user_1], :index_4)
      |> put_dialogs_with_invites([[user_3], user_2], :index_5)
      |> put_dialogs_with_invites([[user_4, user_1], user_3], :index_6)

    cargo_keys =
      Chat.Db.db()
      |> KeyScope.get_cargo_keys(Map.get(invitations_board, :room_key), checkpoints_keys)
      |> fetch_checked_keys()

    board_keys =
      Map.filter(invitations_board, fn {_k, v} -> is_list(v) end)

    assert Enum.any?(
             Map.get(invitations_board, :index_5),
             &MapSet.member?(cargo_keys, &1)
           )

    refute Enum.any?(
             Map.get(invitations_board, :index_6),
             &MapSet.member?(cargo_keys, &1)
           )
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

  defp generate_dialogs_and_cargo_room_invite(context, [recipients, sender]) do
    for recipient <- recipients,
        into: [],
        do:
          sender
          |> Dialogs.find_or_open(recipient |> Chat.Card.from_identity())
          |> create_and_add_room_invite(Map.get(context, :room_identity), sender)
  end

  defp create_and_add_room_invite(dialog, room_identity, user) do
    room_identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(user, dialog)
    |> RoomInviteIndex.add(dialog, user)
    |> then(&read_room_invitatition(dialog, &1, user))
  end

  defp read_room_invitatition(dialog, room_invitation_message, user) do
    Dialogs.read_message(dialog, room_invitation_message, user)
    |> Map.fetch!(:content)
    |> Utils.StorageId.from_json_to_key()
  end

  defp generate_cargo_room(context, user) do
    {room_identity, _room} = Rooms.add(user, "Cargo room", :cargo)
    Map.put(context, :room_identity, room_identity)
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

  defp fetch_checked_keys(keys) do
    keys
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
  end

  defp put_dialogs_with_invites(
         context,
         [recipients, sender],
         step_mark
       ) do
    context
    |> generate_dialogs_and_cargo_room_invite([recipients, sender])
    |> then(&Map.put(context, step_mark, &1))
  end
end
