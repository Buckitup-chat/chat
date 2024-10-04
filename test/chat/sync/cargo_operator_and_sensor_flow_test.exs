defmodule ChatTest.Sync.CargoOperatorAndSensorFlowTest do
  use ChatTest.IsolatedDataCase, dbs: [:sensor, :operator]

  alias Chat.Db.Copying
  alias Chat.Db.Scope.KeyScope
  alias Chat.Messages.RoomInvite

  test "Cargo :: create room export data and accept on sensor db", test_context do
    %{isolated_dbs: test_context.isolated_dbs}
    |> use_db(:sensor)
    |> create_cargo_user
    |> use_db(:operator)
    |> create_operator_user
    |> create_cargo_room
    |> compute_cargo_scope
    |> refute_bad_dialog_keys
    |> assert_minimal_keys_present
    |> copy_cargo_scope_to(:sensor)
    |> use_db(:sensor)
    |> assert_cargo_room_is_acceptable
  end

  defp create_cargo_user(context) do
    "cargo_user_for_sensor"
    |> Chat.User.login()
    |> tap(&Chat.User.register/1)
    |> save_in(context, as: :cargo_user)
  end

  defp create_operator_user(context) do
    "operator_user"
    |> Chat.User.login()
    |> tap(&Chat.User.register/1)
    |> save_in(context, as: :operator_user)
  end

  defp create_cargo_room(context) do
    Chat.User.register(context.cargo_user)
    {identity, room} = Chat.Rooms.add(context.operator_user, "cargo_room")

    dialog =
      Chat.Dialogs.find_or_open(
        context.operator_user,
        context.cargo_user |> Chat.Card.from_identity()
      )

    identity
    |> Map.put(:name, room.name)
    |> RoomInvite.new()
    |> Chat.Dialogs.add_new_message(context.operator_user, dialog)
    |> Chat.RoomInviteIndex.add(dialog, context.operator_user, room.pub_key)
    |> tap(fn {index, message} ->
      Copying.await_written_into(
        [{:dialog_message, dialog |> Enigma.hash(), index, message.id |> Enigma.hash()}],
        Chat.Db.db()
      )
    end)

    Process.sleep(200)

    context
    |> Map.put(:cargo_room, room)
    |> Map.put(:cargo_room_identity, identity)
  end

  defp compute_cargo_scope(context) do
    KeyScope.get_cargo_keys(Chat.Db.db(), context.cargo_room.pub_key, [
      context.cargo_user.public_key
    ])
    |> save_in(context, as: :cargo_scope)
  end

  defp refute_bad_dialog_keys(context) do
    tap(context, fn context ->
      bad_message_keys =
        context.cargo_scope
        |> Enum.filter(&match?({:dialog_message, _, nil, _}, &1))

      assert Enum.empty?(bad_message_keys)
    end)
  end

  defp assert_minimal_keys_present(context) do
    tap(context, fn context ->
      assert context.cargo_scope |> MapSet.size() > 3

      should_have =
        ~w(dialogs dialog_message rooms room_invite room_invite_index)a
        |> MapSet.new()

      scope_key_types =
        context.cargo_scope
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      assert should_have |> MapSet.subset?(scope_key_types)
    end)
  end

  defp copy_cargo_scope_to(context, db) do
    tap(context, fn context ->
      Copying.await_copied(
        Chat.Db.db(),
        context |> db_name(db),
        context.cargo_scope
      )
    end)
  end

  defp assert_cargo_room_is_acceptable(context) do
    tap(context, fn context ->
      invite =
        Chat.Dialogs.room_invite_for_user_to_room(
          context.cargo_user,
          context.cargo_room.pub_key
        )

      refute is_nil(invite)
      assert context.cargo_room_identity == Chat.Dialogs.extract_invite_room_identity(invite)
    end)
  end

  # Utils
  defp save_in(data, context, as: key), do: Map.put(context, key, data)
end
