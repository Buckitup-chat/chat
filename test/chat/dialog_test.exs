defmodule Chat.Dialogs.DialogTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Files
  alias Chat.Memo
  alias Chat.User
  alias Chat.Utils.StorageId

  test "start dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    charlie = User.login("Charlie")

    bob_card = bob |> Card.from_identity()

    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)

    dialog |> Dialogs.add_text(alice, text_message, DateTime.utc_now())
    dialog |> Dialogs.add_image(alice, ["not_image", "text/plain"])
    dialog |> Dialogs.add_image(bob, ["not_image 2", "text/plain"], DateTime.utc_now())

    assert 3 == dialog |> Dialogs.read(bob) |> Enum.count()

    assert_raise RuntimeError, fn -> dialog |> Dialogs.add_text(charlie, "spam") end

    assert_raise(RuntimeError, fn -> dialog |> Dialogs.read(charlie) end)
  end

  test "should create dialog, repoen it, add message and check peer" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    content = "hi"

    initial = Dialogs.find_or_open(alice, bob_card)
    dialog = Dialogs.find_or_open(alice, bob_card)

    assert initial == dialog

    msg = dialog |> Dialogs.add_text(alice, content)

    bob_version = Dialogs.read_message(dialog, msg, bob)

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
    content = "hi memo"

    dialog = Dialogs.find_or_open(alice, bob_card)

    msg = dialog |> Dialogs.add_memo(alice, content)

    bob_version = Dialogs.read_message(dialog, msg, bob)

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
    content = ["text file", "text/plain", "some.txt", 1000 |> to_string()]

    dialog = Dialogs.find_or_open(alice, bob_card)

    msg = dialog |> Dialogs.add_file(alice, content)

    bob_version = Dialogs.read_message(dialog, msg, bob)

    assert :file = bob_version.type

    assert ^content =
             bob_version.content
             |> StorageId.from_json()
             |> Files.get()
  end
end
