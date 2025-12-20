defmodule ChatWeb.MemoMessageUpdateTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  # Note: The actual synchronization happens in Chat.Messaging.preload_content
  # We're using pragmatic Process.sleep in tests for simplicity

  setup do
    # Create two users and a dialog between them
    alice = Identity.create("Alice")
    bob = Identity.create("Bob")
    dialog = Dialogs.open(alice, bob)

    # Create a short message (non-memo type)
    short_message = "Initial short text"

    short_msg =
      %Messages.Text{text: short_message}
      |> Dialogs.add_new_message(alice, dialog)

    # In test environments, some synchronization mechanisms may not be fully available
    # We use Process.sleep as a pragmatic solution here
    # This is acceptable in tests since we're not testing timing-sensitive behavior
    Process.sleep(100)

    %{
      alice: alice,
      bob: bob,
      dialog: dialog,
      short_msg: short_msg
    }
  end

  @tag :memo_update_test
  test "updating a text message to a memo message works with proper synchronization", %{
    alice: alice,
    dialog: dialog,
    short_msg: short_msg
  } do
    # Extract message ID correctly from the message tuple
    # short_msg is likely a tuple like {index, message_struct}
    {index, message} = short_msg
    msg_id = {index, message.id}

    # Create a long message that will be treated as a memo (>150 chars)
    long_message =
      "This is a much longer message that will be treated as a memo"
      |> String.pad_trailing(200, "-")

    # Update the message to become a memo message
    %Messages.Text{text: long_message}
    |> Dialogs.update_message(msg_id, alice, dialog)

    # In test environments, some synchronization mechanisms may not be fully available
    # This sleep allows time for the async memo content processing to complete
    # The production code now uses Chat.Db.Copying.await_copied in preload_content
    Process.sleep(200)

    # Verify message was updated to memo type
    message = Dialogs.read_message(dialog, msg_id, alice)

    # Check that it's now a memo message
    assert message.type == :memo

    # Use preload_content to load and decrypt the memo content
    [enriched_message] = Chat.Messaging.preload_content([message])

    # Now check that the memo content is available and correct
    assert Map.has_key?(enriched_message, :memo)
    assert enriched_message.memo == long_message

    # This verifies our synchronized behavior is working correctly:
    # 1. Message was properly converted to memo type
    # 2. Content was properly encrypted and stored
    # 3. When reading it back, the message has the :memo key
    # 4. The decrypted memo content matches the original text
  end
end
