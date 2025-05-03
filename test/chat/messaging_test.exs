defmodule Chat.MessagingTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.DbKeys
  alias Chat.Identity
  alias Chat.Messaging
  alias Chat.Utils.StorageId

  # Define a test message struct that mimics the real message structs
  defmodule TestMessage do
    defstruct [:type, :content]
  end

  describe "preload_content/2" do
    setup do
      # Common setup for all tests
      # Secret must be 32 bytes
      secret = :crypto.strong_rand_bytes(32)

      %{
        secret: secret,
        create_storage_id: fn key -> StorageId.to_json({key, secret}) end,
        create_test_message: fn type, content -> %TestMessage{type: type, content: content} end,
        create_data_getter: fn db_key, data ->
          fn [^db_key] -> %{db_key => data} end
        end
      }
    end

    test "handles text messages", %{create_test_message: create_test_message} do
      # Create a text message
      text_message = create_test_message.(:text, "Hello, world!")

      # Process the message
      [processed_message] = Messaging.preload_content([text_message], fn _ -> %{} end)

      # Text messages should remain unchanged except for being converted to a map
      assert processed_message.type == :text
      assert processed_message.content == "Hello, world!"
    end

    test "handles file messages", context do
      # Extract context values
      %{
        secret: secret,
        create_storage_id: create_storage_id,
        create_test_message: create_test_message,
        create_data_getter: create_data_getter
      } = context

      # Setup for file message test
      key = "file_key"
      storage_id = create_storage_id.(key)
      file_message = create_test_message.(:file, storage_id)

      db_key = DbKeys.file(key)
      encrypted_data = [Enigma.cipher("file_data", secret)]
      data_getter = create_data_getter.(db_key, encrypted_data)

      # Process the message
      [processed_message] = Messaging.preload_content([file_message], data_getter)

      # File messages should be enriched with file_info and file_url
      assert processed_message.file_info == ["file_data"]
      assert is_binary(processed_message.file_url)
    end

    test "handles image messages", context do
      # Extract context values
      %{
        secret: secret,
        create_storage_id: create_storage_id,
        create_test_message: create_test_message,
        create_data_getter: create_data_getter
      } = context

      # Setup for image message test
      key = "image_key"
      storage_id = create_storage_id.(key)
      image_message = create_test_message.(:image, storage_id)

      db_key = DbKeys.file(key)
      encrypted_data = [Enigma.cipher("image_data", secret)]
      data_getter = create_data_getter.(db_key, encrypted_data)

      # Process the message
      [processed_message] = Messaging.preload_content([image_message], data_getter)

      # Image messages should be enriched with file_info and file_url
      assert processed_message.file_info == ["image_data"]
      assert is_binary(processed_message.file_url)
    end

    test "handles memo messages", context do
      # Extract context values
      %{
        secret: secret,
        create_storage_id: create_storage_id,
        create_test_message: create_test_message,
        create_data_getter: create_data_getter
      } = context

      # Setup for memo message test
      key = "memo_key"
      storage_id = create_storage_id.(key)
      memo_message = create_test_message.(:memo, storage_id)

      db_key = DbKeys.memo(key)
      encrypted_data = Enigma.cipher("memo_data", secret)
      data_getter = create_data_getter.(db_key, encrypted_data)

      # Process the message
      [processed_message] = Messaging.preload_content([memo_message], data_getter)

      # Memo messages should be enriched with memo content
      assert processed_message.memo == "memo_data"
    end

    test "handles unknown message types", %{create_test_message: create_test_message} do
      # Create an unknown message type
      unknown_message = create_test_message.(:unknown, "some_content")

      # Process the message
      [processed_message] = Messaging.preload_content([unknown_message], fn _ -> %{} end)

      # Unknown message types should remain unchanged except for being converted to a map
      assert processed_message.type == :unknown
      assert processed_message.content == "some_content"
    end

    test "handles multiple messages of different types", %{
      create_test_message: create_test_message
    } do
      # Create messages of different types
      text_message = create_test_message.(:text, "Hello, world!")
      unknown_message = create_test_message.(:unknown, "some_content")

      # Process the messages
      processed_messages =
        Messaging.preload_content([text_message, unknown_message], fn _ -> %{} end)

      # All messages should be processed
      assert length(processed_messages) == 2
      assert Enum.at(processed_messages, 0).type == :text
      assert Enum.at(processed_messages, 0).content == "Hello, world!"
      assert Enum.at(processed_messages, 1).type == :unknown
      assert Enum.at(processed_messages, 1).content == "some_content"
    end
  end
end
