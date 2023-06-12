defmodule Chat.Dialogs.DialogTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Content.Files
  alias Chat.Content.Memo
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils.StorageId
  alias Support.FakeData

  test "start dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    charlie = User.login("Charlie")

    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)

    %Messages.Text{text: text_message} |> Dialogs.add_new_message(alice, dialog)

    "not_image"
    |> fake_image
    |> Dialogs.add_new_message(alice, dialog)

    "not_image 2"
    |> fake_image
    |> Dialogs.add_new_message(bob, dialog)
    |> Dialogs.await_saved(dialog)

    assert 3 == dialog |> Dialogs.read(bob) |> Enum.count()

    assert_raise CaseClauseError, fn ->
      %Messages.Text{text: "spam"} |> Dialogs.add_new_message(charlie, dialog)
    end

    assert_raise(CaseClauseError, fn -> dialog |> Dialogs.read(charlie) end)
  end

  test "should create dialog, repoen it, add message and check peer" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    content = "hi"

    initial = Dialogs.find_or_open(alice, bob_card)
    dialog = Dialogs.find_or_open(alice, bob_card)

    assert initial == dialog

    %Messages.Text{text: content}
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_version] = Dialogs.read(dialog, bob)

    assert bob_version.content == content

    alice_key = alice |> User.pub_key()
    bob_key = bob |> User.pub_key()

    assert alice_key == dialog |> Dialogs.peer(bob_card)
    assert alice_key == dialog |> Dialogs.peer(bob_key)
    assert bob_key == dialog |> Dialogs.peer(alice_key)
    assert bob_key == dialog |> Dialogs.peer(alice)

    assert is_binary(Dialogs.key(dialog))
  end

  test "dialog with memo should work" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    content = "hi memo" |> String.pad_trailing(160, "-")

    dialog = Dialogs.find_or_open(alice, bob_card)

    content
    |> make_memo_msg()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_version] = Dialogs.read(dialog, bob)

    assert :memo = bob_version.type

    assert ^content =
             bob_version.content
             |> StorageId.from_json()
             |> Memo.get()
  end

  test "dialog with fle should work" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()

    dialog = Dialogs.find_or_open(alice, bob_card)

    fake_file()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_version] = Dialogs.read(dialog, bob)

    assert :audio = bob_version.type
  end

  test "removed by author message should not be present in dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)

    %Messages.Text{text: text_message} |> Dialogs.add_new_message(alice, dialog)

    "not_image"
    |> fake_image
    |> Dialogs.add_new_message(alice, dialog)

    "not_image 2"
    |> fake_image
    |> Dialogs.add_new_message(bob, dialog)
    |> Dialogs.await_saved(dialog)

    msg_id =
      dialog
      |> Dialogs.read(bob)
      |> Enum.find(&(&1.content == text_message))
      |> then(fn
        nil -> nil
        x -> {x.index, x.id}
      end)

    assert msg_id != nil

    dialog |> Dialogs.delete(alice, msg_id)
    ChangeTracker.await()

    assert nil ==
             dialog
             |> Dialogs.read(bob)
             |> Enum.find(&(&1.content == text_message))
  end

  test "message cannot be removed by a peer in dialog" do
    {alice, bob, _bob_card, dialog} = alice_bob_dialog()
    text_message = "Alice welcomes Bob"

    %Messages.Text{text: text_message} |> Dialogs.add_new_message(alice, dialog)

    "not_image"
    |> fake_image
    |> Dialogs.add_new_message(alice, dialog)

    "not_image 2"
    |> fake_image
    |> Dialogs.add_new_message(bob, dialog)
    |> Dialogs.await_saved(dialog)

    msg_id =
      dialog
      |> Dialogs.read(bob)
      |> Enum.find(&(&1.content == text_message))
      |> then(fn
        nil -> nil
        x -> {x.index, x.id}
      end)

    assert msg_id != nil

    dialog |> Dialogs.delete(bob, msg_id)

    assert nil !=
             dialog
             |> Dialogs.read(bob)
             |> Enum.find(&(&1.content == text_message))
  end

  test "message removal should remove content as well" do
    {alice, _, _, dialog} = alice_bob_dialog()

    "memo here"
    |> make_memo_msg()
    |> Dialogs.add_new_message(alice, dialog)

    "not_image"
    |> fake_image
    |> Dialogs.add_new_message(alice, dialog)

    fake_file()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    dialog
    |> Dialogs.read(alice)
    |> Enum.zip([&Memo.get/1, &Files.get/1, &Files.get/1])
    |> Enum.map(fn {msg, getter} ->
      assert nil != msg.content |> StorageId.from_json() |> then(getter)
      dialog |> Dialogs.delete(alice, {msg.index, msg.id})
      ChangeTracker.await()
      assert nil == msg.content |> StorageId.from_json() |> then(getter)
    end)
  end

  test "message update should replace previous version in dialog" do
    {alice, _, _, dialog} = alice_bob_dialog()
    text = "text here"
    updated_text = "updated text here" |> String.pad_trailing(200, "-")

    "memo here"
    |> make_memo_msg()
    |> Dialogs.add_new_message(alice, dialog)

    %Messages.Text{text: text}
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    assert [_, msg] = dialog |> Dialogs.read(alice)
    assert ^text = msg.content

    msg_id = {msg.index, msg.id}

    updated_text
    |> Messages.Text.new(0)
    |> Dialogs.update_message(msg_id, alice, dialog)
    |> Dialogs.await_saved(dialog)

    assert [_, %{type: :memo} = msg] = dialog |> Dialogs.read(alice)
    assert ^updated_text = msg.content |> StorageId.from_json() |> Memo.get()

    text
    |> Messages.Text.new(0)
    |> Dialogs.update_message(msg_id, alice, dialog)
    |> Dialogs.await_saved(dialog)

    assert [_, %{type: :text, content: ^text}] = dialog |> Dialogs.read(alice)
  end

  test "message should be readable by its id" do
    {alice, _, _, dialog} = alice_bob_dialog()

    "memo here "
    |> make_memo_msg()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    assert [msg] = dialog |> Dialogs.read(alice)

    same_msg = Dialogs.read_message(dialog, {msg.index, msg.id}, alice)

    assert same_msg == msg
  end

  test "gets invite for users to the room" do
    alice = User.login("Alice")
    alice_key = User.register(alice)
    User.await_saved(alice_key)

    bob = User.login("Bob")
    bob_key = User.register(bob)
    User.await_saved(bob_key)
    bob_card = User.by_id(bob_key)
    dialog = Dialogs.find_or_open(alice, bob_card)

    {room_identity1, _room} = Rooms.add(alice, "Private room 1", :private)
    Rooms.await_saved(room_identity1)
    {room_identity2, _room} = Rooms.add(alice, "Private room 2", :private)
    Rooms.await_saved(room_identity2)
    {room_identity3, _room} = Rooms.add(alice, "Private room 3", :private)
    Rooms.await_saved(room_identity3)

    [message1, message2, message3] =
      Stream.map([room_identity1, room_identity2, room_identity3], fn room_identity ->
        room_identity
        |> Messages.RoomInvite.new()
        |> Dialogs.add_new_message(alice, dialog)
        |> tap(&Dialogs.await_saved(&1, dialog))
        |> then(fn {_, msg} -> msg end)
      end)
      |> Enum.to_list()

    invite1 = Chat.Dialogs.room_invite_for_user_to_room(bob, room_identity1.public_key)
    invite2 = Chat.Dialogs.room_invite_for_user_to_room(bob, room_identity2.public_key)
    invite3 = Chat.Dialogs.room_invite_for_user_to_room(bob, room_identity3.public_key)

    assert invite1.id == message1.id
    assert invite2.id == message2.id
    assert invite3.id == message3.id
  end

  defp fake_file do
    FakeData.file()
  end

  defp fake_image(name) do
    FakeData.image(name)
  end

  defp make_memo_msg(text) do
    text
    |> String.pad_trailing(160, "-")
    |> then(&%Messages.Text{text: &1})
  end

  defp alice_bob_dialog do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()

    dialog =
      alice
      |> Dialogs.open(bob_card)

    {alice, bob, bob_card, dialog}
  end
end
