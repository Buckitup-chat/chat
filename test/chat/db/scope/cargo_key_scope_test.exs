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

  test "user and checkpoint got room invites" do
    {[[checkpoint_1], checkpoint_key], [operator], [user]} = setup_test_data(1, 1, 1)

    context =
      %{}
      |> generate_cargo_room(operator)
      |> send_invite(from: operator, to: [checkpoint_1, user], mark_as: :index_1)

    cargo_keys =
      Chat.Db.db()
      |> KeyScope.get_cargo_keys(Map.get(context, :room_key), checkpoint_key)
      |> fetch_checked_keys()

    assert Enum.any?(Map.get(context, :index_1), &MapSet.member?(cargo_keys, &1))
    assert_keys_for_cargo_keys(Map.get(context, :room_key), checkpoint_key, 2)
  end

  test "room invitation should be found in dialog of operator and user by only checkpoints key" do
    {[[checkpoint_1, checkpoint_2], checkpoint_keys], [operator], [user_c, user_d] = _users} =
      setup_test_data(2, 1, 2)

    context =
      %{}
      |> generate_cargo_room(operator)
      |> send_invite(from: operator, to: [checkpoint_1, checkpoint_2], mark_as: :index_1)
      |> send_invite(from: operator, to: user_c, mark_as: :index_2)
      |> send_invite(from: user_c, to: user_d, mark_as: :index_3)

    room_key = context |> Map.get(:room_identity) |> Identity.pub_key()

    assert_keys_for_cargo_keys(room_key, checkpoint_keys, 4)
  end

  test "room invitations found up to 1 handshake" do
    {
      [[checkpoint_1, checkpoint_2, checkpoint_3], checkpoints_keys],
      [operator_1, operator_2],
      [user_1, user_2, user_3, user_4]
    } = setup_test_data(3, 2, 4)

    invitations_board =
      %{}
      |> generate_cargo_room(operator_1)
      |> send_invite(from: operator_1, to: [checkpoint_1, checkpoint_2], mark_as: :index_1)
      |> send_invite(from: operator_2, to: checkpoint_3, mark_as: :index_2)
      |> send_invite(from: operator_1, to: user_1, mark_as: :index_3)
      |> send_invite(from: user_1, to: [user_2, user_4], mark_as: :index_4)
      |> send_invite(from: user_2, to: user_3, mark_as: :index_5)
      |> send_invite(from: user_3, to: [user_4, user_1], mark_as: :index_6)

    cargo_keys =
      Chat.Db.db()
      |> KeyScope.get_cargo_keys(Map.get(invitations_board, :room_key), checkpoints_keys)
      |> fetch_checked_keys()

    assert Enum.any?(Map.get(invitations_board, :index_5), &MapSet.member?(cargo_keys, &1))
    refute Enum.any?(Map.get(invitations_board, :index_6), &MapSet.member?(cargo_keys, &1))
  end

  defp setup_test_data(checkpoints_count, operators_count, users_count) do
    checkpoints = Enum.map(1..checkpoints_count, &("checkpoint#{&1}" |> User.login()))

    checkpoint_keys =
      generate_checkpoints(checkpoints)

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

  defp generate_dialogs_and_cargo_room_invite(context, [sender, recipients]) do
    recipients = if is_list(recipients), do: recipients, else: [recipients]

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

  defp send_invite(context, opts) do
    context
    |> generate_dialogs_and_cargo_room_invite([opts[:from], opts[:to]])
    |> then(&Map.put(context, opts[:mark_as], &1))
  end
end
