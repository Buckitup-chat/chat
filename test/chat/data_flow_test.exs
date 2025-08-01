defmodule Chat.DataFlowTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Content.Memo
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.User
  alias Chat.Utils.StorageId

  test "simple text message" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()

    dialog = alice |> Dialogs.open(bob_card)

    text_message = "Hello from Alice to Bob"
    message = %Messages.Text{text: text_message}

    stored_parcel =
      message
      |> Chat.SignedParcel.wrap_dialog_message(dialog, alice)
      |> Chat.store_parcel(await: true)

    [{processed_key, _processed_msg} | _] = stored_parcel.data
    assert is_integer(elem(processed_key, 2))

    messages = dialog |> Dialogs.read(bob)

    assert length(messages) == 1
    [received_message] = messages

    assert received_message.type == :text
    assert received_message.content == text_message
    assert received_message.is_mine? == false

    alice_messages = dialog |> Dialogs.read(alice)
    assert length(alice_messages) == 1
    [alice_message] = alice_messages
    assert alice_message.content == text_message
    assert alice_message.is_mine? == true
  end

  test "simple memo message" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    dialog = alice |> Dialogs.open(bob_card)

    # Create a memo message (long text content)
    long_text = String.duplicate("This is a long memo message. ", 100)
    memo_message = %Messages.Text{text: long_text}

    # Pack message and store it (all in one function call)
    stored_parcel =
      memo_message
      |> Chat.SignedParcel.wrap_dialog_message(dialog, alice)
      |> Chat.store_parcel(await: true)

    # For a long message, the parcel should contain both the message and the memo attachments
    # Messages with memo content will have multiple items in the parcel
    assert length(stored_parcel.data) > 1

    # Find the dialog message key
    dialog_msg_entry =
      Enum.find(stored_parcel.data, fn {key, _} -> match?({:dialog_message, _, _, _}, key) end)

    assert dialog_msg_entry != nil
    {{:dialog_message, _dialog_hash, index, _msg_id}, msg} = dialog_msg_entry

    assert is_integer(index)
    assert msg.type == :memo
    refute msg.content == long_text

    # Read messages back
    messages = dialog |> Dialogs.read(bob)

    assert length(messages) == 1
    [received_message] = messages

    assert received_message.type == :memo
    refute received_message.content == long_text

    memo_ref = received_message.content
    assert is_binary(memo_ref)

    memo_key_secret = StorageId.from_json(memo_ref)
    decoded_memo = Memo.get(memo_key_secret)
    assert decoded_memo == long_text

    assert received_message.is_mine? == false

    # Verify alice can also read the message
    alice_messages = dialog |> Dialogs.read(alice)
    assert length(alice_messages) == 1
    [alice_message] = alice_messages
    assert alice_message.content == memo_ref
    assert alice_message.is_mine? == true
  end

  test "text edited into memo" do
    # Create users and dialog
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    dialog = alice |> Dialogs.open(bob_card)

    # Create a short text message
    short_text = "This is a short message"
    text_message = %Messages.Text{text: short_text, timestamp: System.system_time(:second)}

    # Pack message and store it
    stored_parcel =
      text_message
      |> Chat.SignedParcel.wrap_dialog_message(dialog, alice)
      |> Chat.store_parcel(await: true)

    # Get the dialog message data
    dialog_msg_entry =
      Enum.find(stored_parcel.data, fn {key, _} -> match?({:dialog_message, _, _, _}, key) end)

    assert dialog_msg_entry != nil
    {{:dialog_message, _dialog_hash, _index, _msg_id}, msg} = dialog_msg_entry

    # Verify it's stored as a text message
    assert msg.type == :text

    # Read the message back to verify its content
    [original_message] = dialog |> Dialogs.read(bob)
    assert original_message.content == short_text

    # For the update, we'll create a new message with longer content
    # Now we can preserve the message ID to properly simulate an edit
    long_text = String.duplicate("This is now a very long message. ", 100)

    # Extract the message key information to preserve for the update
    {{:dialog_message, _dialog_hash, index, _msg_id_hash}, message} = dialog_msg_entry

    orig_msg_id = message.id

    # Create updated message with new content
    updated_message = %Messages.Text{
      text: long_text,
      timestamp: System.system_time(:second)
    }

    updated_parcel =
      updated_message
      |> Chat.SignedParcel.wrap_dialog_message(dialog, alice, id: orig_msg_id, index: index)
      |> Chat.store_parcel(await: true)

    # Verify the updated parcel contains multiple entries (memo attachments)
    assert length(updated_parcel.data) > 1

    # Find the dialog message entry in the updated parcel
    updated_msg_entry =
      Enum.find(updated_parcel.data, fn {key, _} -> match?({:dialog_message, _, _, _}, key) end)

    assert updated_msg_entry != nil
    {{:dialog_message, _dialog_hash2, _index2, _msg_id2}, updated_msg} = updated_msg_entry

    # Verify the message is now a memo type
    assert updated_msg.type == :memo
    refute updated_msg.content == long_text

    # Read the updated message from the dialog
    # Since we preserved the message ID and index, we should only have one message
    # that has been updated from text to memo type
    updated_messages = dialog |> Dialogs.read(bob)
    # We should only have one message - the updated one
    assert length(updated_messages) == 1

    # Get the message and verify it's now a memo
    [updated_message] = updated_messages
    assert updated_message.type == :memo

    # Get the memo content
    memo_ref = updated_message.content
    memo_key_secret = StorageId.from_json(memo_ref)
    decoded_memo = Memo.get(memo_key_secret)

    # Verify the memo content matches the updated text
    assert decoded_memo == long_text
  end

  # TODO: deal with 2 messages on update
end
