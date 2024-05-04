defmodule ChatTest.Rooms.SpamRoomTest do
  use ExUnit.Case, async: true

  alias Chat.Db
  alias Chat.Messages.Text
  alias Chat.Proto.Identify
  alias Chat.Rooms
  alias Chat.User

  test "room should not store spam messages" do
    %{}
    |> create_room_user_and_spammer
    |> user_adds_messages
    |> assert_room_stored_user_messages
    |> spammer_adds_messages
    |> refute_room_stored_spammer_messages
  end

  defp create_room_user_and_spammer(context) do
    alice = User.login("User Alice")
    sally = User.login("Spammer Sally")
    {room_identity, _room} = Rooms.add(alice, "Alice Private room", :private)
    await_key_written({:rooms, room_identity |> Identify.pub_key()})
    room = Rooms.get(room_identity |> Identify.pub_key())

    context
    |> Map.merge(%{
      user: alice,
      spammer: sally,
      room: room,
      room_identity: room_identity
    })
  end

  def user_adds_messages(context) do
    1..4
    |> Enum.map(fn i ->
      "hello #{i}"
      |> Text.new(i)
      |> Rooms.add_new_message(context.user, context.room_identity)
    end)
    |> Enum.map(fn {index, room_msg} ->
      Chat.DbKeys.room_message(room_msg, index: index, room: context.room)
    end)
    |> tap(&await_key_written/1)

    context
    |> Map.put(:user_messages, 4)
  end

  defp assert_room_stored_user_messages(context) do
    tap(context, fn context ->
      messages =
        Chat.Rooms.read(context.room, context.room_identity)
        |> Enum.frequencies_by(& &1.author_key)

      expected_messages = %{
        (context.user |> Identify.pub_key()) => context.user_messages
      }

      assert expected_messages == messages
    end)
  end

  def spammer_adds_messages(context) do
    fake_room_identity =
      context.user
      |> Map.put(:public_key, context.room.pub_key)

    5..8
    |> Enum.map(fn i ->
      "spam #{i}"
      |> Text.new(i)
      |> Rooms.add_new_message(context.spammer, fake_room_identity)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {index, room_msg} ->
      Chat.DbKeys.room_message(room_msg, index: index, room: context.room)
    end)
    |> tap(&await_key_written/1)

    context
    |> Map.put(:spam_messages, 4)
  end

  defp refute_room_stored_spammer_messages(context) do
    tap(context, fn context ->
      messages =
        Chat.Rooms.read(context.room, context.room_identity)
        |> Enum.frequencies_by(& &1.author_key)

      user_key = context.user |> Identify.pub_key()

      expected_messages = %{
        user_key => context.user_messages
      }

      assert expected_messages == messages

      stored_messages_count =
        Chat.Db.db()
        |> CubDB.select(
          min_key: Chat.DbKeys.room_message(0, index: 0, room: context.room),
          max_key: Chat.DbKeys.room_message(0, index: nil, room: context.room)
        )
        |> Enum.count()

      assert context.user_messages == stored_messages_count
    end)
  end

  defp await_key_written(keys) when is_list(keys) do
    Db.Copying.await_written_into(keys, Db.db())
  end

  defp await_key_written(key) do
    Db.Copying.await_written_into([key], Db.db())
  end
end
