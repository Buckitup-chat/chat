defmodule Chat.RoomDataFlowTest do
  use ExUnit.Case, async: true

  alias Chat.Content.Memo
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils.StorageId

  @moduledoc """
  Tests for room message data flow, mirroring the test cases from DataFlowTest but for rooms.
  """

  test "simple text message in room" do
    alice = User.login("Alice")
    {room_identity, room} = alice |> Rooms.add("Alice's Room")

    text_message = "Hello from Alice to the room"
    message = %Messages.Text{text: text_message, timestamp: System.system_time(:second)}

    message
    |> Chat.SignedParcel.wrap_room_message(room_identity, alice)
    |> tap(fn parcel ->
      assert Chat.SignedParcel.sign_valid?(parcel, alice.public_key)
    end)
    |> Chat.store_parcel(await: true)

    messages = room |> Rooms.read(room_identity)

    assert length(messages) == 1
    [received_message] = messages

    assert received_message.type == :text
    assert received_message.content == text_message
    assert received_message.timestamp == message.timestamp

    alice_key = alice |> Identity.pub_key()
    assert received_message.author_key == alice_key
  end

  test "simple memo message in room" do
    alice = User.login("Alice")
    {room_identity, room} = alice |> Rooms.add("Alice's Room")

    long_text = String.duplicate("This is a long memo message for a room. ", 100)
    memo_message = %Messages.Text{text: long_text, timestamp: System.system_time(:second)}

    memo_message
    |> Chat.SignedParcel.wrap_room_message(room_identity, alice)
    |> tap(fn parcel ->
      assert Chat.SignedParcel.sign_valid?(parcel, alice.public_key)
    end)
    |> Chat.store_parcel(await: true)

    messages = room |> Rooms.read(room_identity)

    assert length(messages) == 1
    [received_message] = messages

    assert received_message.type == :memo
    refute received_message.content == long_text

    memo_ref = received_message.content
    assert is_binary(memo_ref)

    memo_key_secret = StorageId.from_json(memo_ref)
    decoded_memo = Memo.get(memo_key_secret)
    assert decoded_memo == long_text

    alice_key = alice |> Identity.pub_key()
    assert received_message.author_key == alice_key
  end

  test "text edited into memo in room" do
    alice = User.login("Alice")
    {room_identity, room} = alice |> Rooms.add("Alice's Room")

    short_text = "This is a short room message"
    text_message = %Messages.Text{text: short_text, timestamp: System.system_time(:second)}

    text_message
    |> Chat.SignedParcel.wrap_room_message(room_identity, alice)
    |> tap(fn parcel ->
      assert Chat.SignedParcel.sign_valid?(parcel, alice.public_key)
    end)
    |> Chat.store_parcel(await: true)

    [original_message] = room |> Rooms.read(room_identity)
    assert original_message.content == short_text
    assert original_message.type == :text

    long_text = String.duplicate("This is now a very long message for a room. ", 100)

    updated_message = %Messages.Text{
      text: long_text,
      timestamp: System.system_time(:second)
    }

    updated_message
    |> Chat.SignedParcel.wrap_room_message(room_identity, alice,
      # Use the original message ID
      id: original_message.id,
      # Use the original message index
      index: original_message.index
    )
    |> tap(fn parcel ->
      assert Chat.SignedParcel.sign_valid?(parcel, alice.public_key)
    end)
    |> Chat.store_parcel(await: true)

    updated_messages = room |> Rooms.read(room_identity)
    assert length(updated_messages) == 1

    [updated_message] = updated_messages
    assert updated_message.type == :memo

    memo_ref = updated_message.content
    memo_key_secret = StorageId.from_json(memo_ref)
    decoded_memo = Memo.get(memo_key_secret)

    assert decoded_memo == long_text

    alice_key = alice |> Identity.pub_key()
    assert updated_message.author_key == alice_key
  end

  test "wrapped room message with verification" do
    alice = User.login("Alice")
    {room_identity, room} = alice |> Rooms.add("Alice's Room")

    text_message = "Hello from Alice to the room"
    message = %Messages.Text{text: text_message}

    message
    |> Chat.SignedParcel.wrap_room_message(room_identity, alice)
    |> tap(fn parcel ->
      assert Chat.SignedParcel.sign_valid?(parcel, alice.public_key)
    end)
    |> Chat.store_parcel(await: true)

    # Room message verification could be added in the future similar to dialog messages
    # We might need to implement scope_valid? logic for room messages

    messages = room |> Rooms.read(room_identity)
    assert length(messages) == 1
    [received_message] = messages
    assert received_message.content == text_message

    alice_key = alice |> Identity.pub_key()
    assert received_message.author_key == alice_key
  end
end
