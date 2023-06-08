defmodule Chat.Db.Scope.KeyScopeTest do
  use ExUnit.Case, async: false

  alias Chat.Db.ChangeTracker

  alias Chat.{
    Card,
    ChunkedFiles,
    Dialogs,
    FileIndex,
    Identity,
    MemoIndex,
    Messages,
    RoomInviteIndex,
    Rooms,
    User,
    Utils
  }

  alias Chat.Db.Scope.KeyScope
  alias Support.FakeData

  describe "get_keys/2" do
    test "fetches messages and content belonging to specified dialogs and rooms" do
      alice = User.login("Alice")
      User.register(alice)
      alice_key = Identity.pub_key(alice)

      bob = User.login("Bob")
      User.register(bob)
      bob_card = Card.from_identity(bob)
      bob_key = Identity.pub_key(bob)

      charlie = User.login("Charlie")
      User.register(charlie)
      charlie_card = Card.from_identity(charlie)
      charlie_key = Identity.pub_key(charlie)

      alice_bob_dialog = Dialogs.find_or_open(alice, bob_card)

      {_index, alice_bob_message} =
        "Alice welcomes Bob"
        |> Messages.Text.new(1)
        |> Dialogs.add_new_message(alice, alice_bob_dialog)

      {_index, bob_alice_message} =
        "Bob greets Alice"
        |> Messages.Text.new(1)
        |> Dialogs.add_new_message(bob, alice_bob_dialog)

      {_index, bob_alice_memo_message} =
        msg =
        "-"
        |> String.duplicate(151)
        |> Messages.Text.new(1)
        |> Dialogs.add_new_message(bob, alice_bob_dialog)
        |> MemoIndex.add(alice_bob_dialog, bob)

      bob_alice_memo_key =
        Dialogs.read_message(alice_bob_dialog, msg, bob)
        |> Map.fetch!(:content)
        |> Utils.StorageId.from_json_to_key()

      bob_charlie_dialog = Dialogs.find_or_open(bob, charlie_card)

      {_index, bob_charlie_message} =
        "Bob greets Charlie"
        |> Messages.Text.new(1)
        |> Dialogs.add_new_message(bob, bob_charlie_dialog)

      {_index, bob_charlie_memo_message} =
        msg =
        "-"
        |> String.duplicate(151)
        |> Messages.Text.new(1)
        |> Dialogs.add_new_message(bob, bob_charlie_dialog)
        |> MemoIndex.add(bob_charlie_dialog, bob)

      bob_charlie_memo_key =
        Dialogs.read_message(bob_charlie_dialog, msg, bob)
        |> Map.fetch!(:content)
        |> Utils.StorageId.from_json_to_key()

      {room_identity, first_room} = Rooms.add(alice, "Alice, Bob and Charlie room", :request)
      first_room_key = room_identity |> Identity.pub_key()

      room_invite =
        room_identity
        |> Messages.RoomInvite.new()
        |> Dialogs.add_new_message(alice, alice_bob_dialog)
        |> RoomInviteIndex.add(alice_bob_dialog, alice)

      room_invite_key =
        Dialogs.read_message(alice_bob_dialog, room_invite, alice)
        |> Map.fetch!(:content)
        |> Utils.StorageId.from_json_to_key()

      ChangeTracker.await()

      Rooms.add_request(first_room_key, charlie, 1)
      Rooms.approve_request(first_room_key, charlie_key, room_identity, [])

      {_index, alice_first_room_message} =
        "Hello first room from Alice"
        |> Messages.Text.new(1)
        |> Rooms.add_new_message(alice, first_room.pub_key)

      {_index, bob_first_room_message} =
        "Hello first room from Bob"
        |> Messages.Text.new(1)
        |> Rooms.add_new_message(bob, first_room.pub_key)

      {_index, charlie_first_room_message} =
        "Hello first room from Charlie"
        |> Messages.Text.new(1)
        |> Rooms.add_new_message(charlie, first_room.pub_key)

      %Messages.File{data: image_data} = image = FakeData.image("1.pp")
      [first_file_key, encoded_chunk_secret, _, _, _, _] = image_data
      chunk_secret = Base.decode64!(encoded_chunk_secret)

      {_index, first_image_message} =
        image
        |> Map.put(:timestamp, 4)
        |> Rooms.add_new_message(charlie, first_room.pub_key)

      FileIndex.save(
        first_file_key,
        first_room.pub_key,
        first_image_message.id,
        chunk_secret
      )

      ChunkedFiles.new_upload(first_file_key)
      ChunkedFiles.save_upload_chunk(first_file_key, {0, 17}, 30, "some part of info ")
      # ChangeTracker.await({:file_chunk, first_file_key, 0, 17})
      ChunkedFiles.save_upload_chunk(first_file_key, {18, 29}, 30, "another part")

      {room_identity, second_room} = Rooms.add(bob, "Bob and Charlie room")
      second_room_key = second_room.pub_key
      Rooms.Registry.await_saved(second_room_key)
      Rooms.add_request(second_room_key, charlie, 1)
      Rooms.approve_request(second_room_key, charlie_key, room_identity, [])

      {_index, bob_second_room_message} =
        "Hello second room from Bob"
        |> Messages.Text.new(1)
        |> Rooms.add_new_message(bob, second_room.pub_key)

      {_index, charlie_second_room_message} =
        "Hello second room from Charlie"
        |> Messages.Text.new(1)
        |> Rooms.add_new_message(charlie, second_room.pub_key)

      %Messages.File{data: image_data} = image = FakeData.image("2.pp")
      [second_file_key, encoded_chunk_secret, _, _, _, _] = image_data
      chunk_secret = Base.decode64!(encoded_chunk_secret)

      {_index, second_image_message} =
        image
        |> Map.put(:timestamp, 4)
        |> Rooms.add_new_message(charlie, second_room.pub_key)

      FileIndex.save(
        second_file_key,
        second_room.pub_key,
        second_image_message.id,
        chunk_secret
      )

      ChunkedFiles.new_upload(second_file_key)
      ChunkedFiles.save_upload_chunk(second_file_key, {0, 17}, 30, "some part of info ")
      # ChangeTracker.await({:file_chunk, second_file_key, 0, 17})
      ChunkedFiles.save_upload_chunk(second_file_key, {18, 29}, 30, "another part")

      assert keys =
               KeyScope.get_keys(Chat.Db.db(), [
                 Identity.pub_key(alice),
                 first_room.pub_key
               ])

      assert Enum.member?(keys, {:chunk_key, {:file_chunk, first_file_key, 0, 17}})
      assert Enum.member?(keys, {:chunk_key, {:file_chunk, first_file_key, 18, 29}})
      refute Enum.member?(keys, {:chunk_key, {:file_chunk, second_file_key, 0, 17}})
      refute Enum.member?(keys, {:chunk_key, {:file_chunk, second_file_key, 18, 29}})

      assert Enum.count(keys, fn key ->
               match?(
                 {:chunk_key, {:file_chunk, _file_key, _chunk_start, _chunk_end}},
                 key
               )
             end) == 2

      assert Enum.member?(keys, {:file_chunk, first_file_key, 0, 17})
      assert Enum.member?(keys, {:file_chunk, first_file_key, 18, 29})
      refute Enum.member?(keys, {:file_chunk, second_file_key, 0, 17})
      refute Enum.member?(keys, {:file_chunk, second_file_key, 18, 29})

      assert Enum.count(keys, fn key ->
               match?({:file_chunk, _file_key, _chunk_start, _chunk_end}, key)
             end) == 2

      assert Enum.member?(keys, {:file, first_file_key})
      refute Enum.member?(keys, {:file, second_file_key})

      assert Enum.count(keys, fn key -> match?({:file, _file_key}, key) end) == 1

      alice_bob_dialog_binhash = alice_bob_dialog |> Dialogs.key()
      bob_charlie_dialog_binhash = bob_charlie_dialog |> Dialogs.key()

      assert Enum.member?(keys, {:dialogs, alice_bob_dialog_binhash})
      refute Enum.member?(keys, {:dialogs, bob_charlie_dialog_binhash})
      assert Enum.count(keys, fn key -> match?({:dialogs, _dialog_binhash}, key) end) == 1

      assert Enum.any?(keys, fn key ->
               message_hash = alice_bob_message.id |> Enigma.hash()
               match?({:dialog_message, _dialog_key, _index, ^message_hash}, key)
             end)

      assert Enum.any?(keys, fn key ->
               message_hash = bob_alice_message.id |> Enigma.hash()
               match?({:dialog_message, _dialog_key, _index, ^message_hash}, key)
             end)

      assert Enum.any?(keys, fn key ->
               message_hash = bob_alice_memo_message.id |> Enigma.hash()
               match?({:dialog_message, _dialog_key, _index, ^message_hash}, key)
             end)

      refute Enum.any?(keys, fn key ->
               message_hash = bob_charlie_message.id |> Enigma.hash()
               match?({:dialog_message, _dialog_key, _index, ^message_hash}, key)
             end)

      refute Enum.any?(keys, fn key ->
               message_hash = bob_charlie_memo_message.id |> Enigma.hash()
               match?({:dialog_message, _dialog_key, _index, ^message_hash}, key)
             end)

      assert Enum.count(keys, fn key ->
               match?({:dialog_message, _dialog_key, _index, _message_hash}, key)
             end) == 4

      assert Enum.member?(
               keys,
               {:file_index, first_room_key, first_file_key, first_image_message.id}
             )

      refute Enum.member?(
               keys,
               {:file_index, second_room_key, second_file_key, second_image_message.id}
             )

      assert Enum.count(keys, fn key ->
               match?({:file_index, _reader_hash, _file_key, _message_id}, key)
             end) == 1

      assert Enum.member?(keys, {:memo, bob_alice_memo_key})
      refute Enum.member?(keys, {:memo, bob_charlie_memo_key})
      assert Enum.count(keys, fn key -> match?({:memo, _memo_key}, key) end) == 1

      assert Enum.member?(keys, {:memo_index, alice_key, bob_alice_memo_key})

      assert Enum.count(keys, fn key ->
               match?({:memo_index, _reader_hash, _memo_key}, key)
             end) == 1

      assert Enum.member?(keys, {:rooms, first_room_key})
      refute Enum.member?(keys, {:rooms, second_room_key})
      assert Enum.count(keys, fn key -> match?({:rooms, _room_hash}, key) end) == 1
      assert Enum.member?(keys, {:room_invite, room_invite_key})
      assert Enum.count(keys, fn key -> match?({:room_invite, _invite_key}, key) end) == 1
      assert Enum.member?(keys, {:room_invite_index, alice_key, room_invite_key})

      assert Enum.count(keys, fn key ->
               match?({:room_invite_index, _reader_hash, _invite_key}, key)
             end) == 1

      assert Enum.any?(keys, fn key ->
               message_hash = alice_first_room_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      assert Enum.any?(keys, fn key ->
               message_hash = bob_first_room_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      assert Enum.any?(keys, fn key ->
               message_hash = charlie_first_room_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      assert Enum.any?(keys, fn key ->
               message_hash = first_image_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      refute Enum.any?(keys, fn key ->
               message_hash = bob_second_room_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      refute Enum.any?(keys, fn key ->
               message_hash = charlie_second_room_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      refute Enum.any?(keys, fn key ->
               message_hash = second_image_message.id |> Enigma.hash()
               match?({:room_message, _room_key, _index, ^message_hash}, key)
             end)

      assert Enum.count(keys, fn key ->
               match?({:room_message, _room_key, _index, _message_hash}, key)
             end) == 5

      assert Enum.member?(keys, {:users, alice_key})
      assert Enum.member?(keys, {:users, bob_key})
      assert Enum.member?(keys, {:users, charlie_key})
    end
  end
end
