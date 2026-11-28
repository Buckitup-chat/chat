defmodule Chat.Dialogs.DialogTest do
  use ChatWeb.DataCase, async: true

  import Chat.Test.DialogsFixtures,
    only: [add_text_and_two_images: 4, alice_bob_dialog: 0, memo_message: 1]

  alias Chat.Card
  alias Chat.Content.Memo
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias Chat.Utils.StorageId
  alias Support.FakeData

  test "start dialog" do
    {alice, bob, _bob_card, dialog} = alice_bob_dialog()
    charlie = User.login("Charlie")

    add_text_and_two_images(dialog, alice, bob, "Alice welcomes Bob")

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
    {alice, bob, bob_card} = alice_and_bob()
    dialog = Dialogs.find_or_open(alice, bob_card)
    content = "hi memo" |> String.pad_trailing(160, "-")

    content
    |> memo_message()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_version] = Dialogs.read(dialog, bob)

    assert :memo = bob_version.type
    assert ^content = bob_version.content |> StorageId.from_json() |> Memo.get()
  end

  test "dialog with file should work" do
    {alice, bob, bob_card} = alice_and_bob()
    dialog = Dialogs.find_or_open(alice, bob_card)

    FakeData.file()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_version] = Dialogs.read(dialog, bob)

    assert :audio = bob_version.type
  end

  test "message should be readable by its id" do
    {alice, _, _, dialog} = alice_bob_dialog()

    "memo here "
    |> memo_message()
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    assert [msg] = dialog |> Dialogs.read(alice)

    same_msg = Dialogs.read_message(dialog, {msg.index, msg.id}, alice)

    assert same_msg == msg
  end

  test "gets invite for users to the room" do
    {alice, _alice_key} = register_user("Alice")
    {bob, bob_key} = register_user("Bob")
    dialog = Dialogs.find_or_open(alice, User.by_id(bob_key))

    room_identities = Enum.map(1..3, &add_private_room(alice, "Private room #{&1}"))
    messages = Enum.map(room_identities, &send_room_invite(&1, alice, dialog))

    invite_ids =
      Enum.map(room_identities, &Dialogs.room_invite_for_user_to_room(bob, &1.public_key).id)

    assert invite_ids == Enum.map(messages, & &1.id)
  end

  test "message from unregistred user works" do
    alice = User.login("Alice")
    alice_card = alice |> Card.from_identity()

    bob = Identity.create("Bob")
    bob_card = bob |> Card.from_identity()
    content = "hi"

    initial = Dialogs.find_or_open(alice, bob_card)
    dialog = Dialogs.find_or_open(bob, alice_card)

    assert initial == dialog

    %Messages.Text{text: content}
    |> Dialogs.add_new_message(alice, dialog)
    |> Dialogs.await_saved(dialog)

    [bob_version] = Dialogs.read(dialog, bob)

    assert bob_version.content == content
  end

  # --- Helpers ---

  defp alice_and_bob do
    alice = User.login("Alice")
    bob = User.login("Bob")
    {alice, bob, Card.from_identity(bob)}
  end

  defp register_user(name) do
    user = User.login(name)
    key = User.register(user)
    User.await_saved(key)
    {user, key}
  end

  defp add_private_room(owner, name) do
    {room_identity, _room} = Rooms.add(owner, name, :private)
    Rooms.await_saved(room_identity)
    room_identity
  end

  defp send_room_invite(room_identity, sender, dialog) do
    room_identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(sender, dialog)
    |> tap(&Dialogs.await_saved(&1, dialog))
    |> then(fn {_, msg} -> msg end)
  end
end
