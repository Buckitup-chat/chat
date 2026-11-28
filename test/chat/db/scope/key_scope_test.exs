defmodule Chat.Db.Scope.KeyScopeTest do
  use ExUnit.Case, async: true, group: :cubdb

  import Chat.Test.KeyScopeFixtures

  alias Chat.Dialogs

  setup_all :build_key_scope_world

  describe "get_keys/2 dialogs" do
    test "includes only dialogs of the given user", ctx do
      assert {:dialogs, Dialogs.key(ctx.alice_bob_dialog)} in ctx.keys
      refute {:dialogs, Dialogs.key(ctx.bob_charlie_dialog)} in ctx.keys
      assert kind_count(ctx.keys, :dialogs) == 1
    end

    test "includes messages of the given user's dialogs only", ctx do
      assert has_message_key?(ctx.keys, :dialog_message, ctx.alice_bob_message)
      assert has_message_key?(ctx.keys, :dialog_message, ctx.bob_alice_message)
      assert has_message_key?(ctx.keys, :dialog_message, ctx.bob_alice_memo_message)
      refute has_message_key?(ctx.keys, :dialog_message, ctx.bob_charlie_message)
      refute has_message_key?(ctx.keys, :dialog_message, ctx.bob_charlie_memo_message)
      assert kind_count(ctx.keys, :dialog_message) == 4
    end

    test "includes memos and memo index of the given user's dialogs only", ctx do
      assert {:memo, ctx.bob_alice_memo_key} in ctx.keys
      refute {:memo, ctx.bob_charlie_memo_key} in ctx.keys
      assert kind_count(ctx.keys, :memo) == 1

      assert {:memo_index, ctx.alice_key, ctx.bob_alice_memo_key} in ctx.keys
      assert kind_count(ctx.keys, :memo_index) == 1
    end
  end

  describe "get_keys/2 users" do
    test "includes all registered users", ctx do
      assert {:users, ctx.alice_key} in ctx.keys
      assert {:users, ctx.bob_key} in ctx.keys
      assert {:users, ctx.charlie_key} in ctx.keys
    end
  end

  describe "get_keys/2 rooms" do
    test "includes only the given room", ctx do
      assert {:rooms, ctx.first_room_key} in ctx.keys
      refute {:rooms, ctx.second_room_key} in ctx.keys
      assert kind_count(ctx.keys, :rooms) == 1
    end

    test "includes the room invite and its index from the user's dialog", ctx do
      assert {:room_invite, ctx.room_invite_key} in ctx.keys
      assert kind_count(ctx.keys, :room_invite) == 1

      assert {:room_invite_index, ctx.alice_key, ctx.room_invite_key} in ctx.keys
      assert kind_count(ctx.keys, :room_invite_index) == 1
    end

    test "includes messages of the given room only", ctx do
      assert has_message_key?(ctx.keys, :room_message, ctx.alice_first_room_message)
      assert has_message_key?(ctx.keys, :room_message, ctx.bob_first_room_message)
      assert has_message_key?(ctx.keys, :room_message, ctx.charlie_first_room_message)
      assert has_message_key?(ctx.keys, :room_message, ctx.first_image_message)
      refute has_message_key?(ctx.keys, :room_message, ctx.bob_second_room_message)
      refute has_message_key?(ctx.keys, :room_message, ctx.charlie_second_room_message)
      refute has_message_key?(ctx.keys, :room_message, ctx.second_image_message)
      assert kind_count(ctx.keys, :room_message) == 4
    end
  end

  describe "get_keys/2 files" do
    test "includes the file and file index of the given room only", ctx do
      assert {:file, ctx.first_file_key} in ctx.keys
      refute {:file, ctx.second_file_key} in ctx.keys
      assert kind_count(ctx.keys, :file) == 1

      first_index =
        {:file_index, ctx.first_room_key, ctx.first_file_key, ctx.first_image_message.id}

      second_index =
        {:file_index, ctx.second_room_key, ctx.second_file_key, ctx.second_image_message.id}

      assert first_index in ctx.keys
      refute second_index in ctx.keys
      assert kind_count(ctx.keys, :file_index) == 1
    end

    test "includes chunks of files in the given room only", ctx do
      for range <- [{0, 17}, {18, 29}] do
        assert file_chunk(ctx.first_file_key, range) in ctx.keys
        assert {:chunk_key, file_chunk(ctx.first_file_key, range)} in ctx.keys
        refute file_chunk(ctx.second_file_key, range) in ctx.keys
        refute {:chunk_key, file_chunk(ctx.second_file_key, range)} in ctx.keys
      end

      assert kind_count(ctx.keys, :file_chunk) == 2
      assert chunk_key_count(ctx.keys) == 2
    end
  end

  defp file_chunk(file_key, {chunk_start, chunk_end}),
    do: {:file_chunk, file_key, chunk_start, chunk_end}
end
