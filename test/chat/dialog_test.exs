defmodule Chat.Dialogs.DialogTest do
  use ExUnit.Case, async: true

  alias Chat.Card
  alias Chat.Dialogs
  alias Chat.Files
  alias Chat.Images
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

  test "removed by author message should not be present in dialog" do
    alice = User.login("Alice")
    bob = User.login("Bob")
    bob_card = bob |> Card.from_identity()
    text_message = "Alice welcomes Bob"

    dialog =
      alice
      |> Dialogs.open(bob_card)

    dialog |> Dialogs.add_text(alice, text_message, DateTime.utc_now())
    dialog |> Dialogs.add_image(alice, ["not_image", "text/plain"])
    dialog |> Dialogs.add_image(bob, ["not_image 2", "text/plain"], DateTime.utc_now())

    msg_id =
      dialog
      |> Dialogs.read(bob)
      |> Enum.find(&(&1.content == text_message))
      |> then(fn
        nil -> nil
        x -> {x.timestamp, x.id}
      end)

    assert msg_id != nil

    dialog |> Dialogs.delete(alice, msg_id)

    assert nil ==
             dialog
             |> Dialogs.read(bob)
             |> Enum.find(&(&1.content == text_message))
  end

  test "message cannot be removed by a peer in dialog" do
    {alice, bob, _bob_card, dialog} = alice_bob_dialog()
    text_message = "Alice welcomes Bob"

    dialog |> Dialogs.add_text(alice, text_message, DateTime.utc_now())
    dialog |> Dialogs.add_image(alice, ["not_image", "text/plain"])
    dialog |> Dialogs.add_image(bob, ["not_image 2", "text/plain"], DateTime.utc_now())

    msg_id =
      dialog
      |> Dialogs.read(bob)
      |> Enum.find(&(&1.content == text_message))
      |> then(fn
        nil -> nil
        x -> {x.timestamp, x.id}
      end)

    assert msg_id != nil

    dialog |> Dialogs.delete(bob, msg_id)

    assert nil !=
             dialog
             |> Dialogs.read(bob)
             |> Enum.find(&(&1.content == text_message))
  end

  test "message removal shoukld remove content as well" do
    {alice, _, _, dialog} = alice_bob_dialog()

    time = DateTime.utc_now() |> DateTime.add(-10, :second)

    dialog |> Dialogs.add_memo(alice, "memo here", time)

    dialog
    |> Dialogs.add_image(alice, ["not_image", "text/plain"], time |> DateTime.add(1, :second))

    dialog
    |> Dialogs.add_file(
      alice,
      ["not_image 2", "text/plain", "file.txt", "100 B"],
      time |> DateTime.add(2, :second)
    )

    dialog
    |> Dialogs.read(alice)
    |> Enum.zip([&Memo.get/1, &Images.get/1, &Files.get/1])
    |> Enum.map(fn {msg, getter} ->
      assert nil != msg.content |> StorageId.from_json() |> then(getter)
      dialog |> Dialogs.delete(alice, {msg.timestamp, msg.id})
      assert nil == msg.content |> StorageId.from_json() |> then(getter)
    end)
  end

  test "message update should replace previous version in dialog" do
    {alice, _, _, dialog} = alice_bob_dialog()
    time = DateTime.utc_now() |> DateTime.add(-10, :second)
    text = "text here"
    updated_text = "updated text here"

    dialog |> Dialogs.add_memo(alice, "memo here", time)
    dialog |> Dialogs.add_text(alice, text, time |> DateTime.add(1, :second))

    assert [_, msg] = dialog |> Dialogs.read(alice)
    assert ^text = msg.content

    msg_id = {msg.timestamp, msg.id}
    dialog |> Dialogs.update(alice, msg_id, {:memo, updated_text})

    assert [_, %{type: :memo} = msg] = dialog |> Dialogs.read(alice)
    assert ^updated_text = msg.content |> StorageId.from_json() |> Memo.get()

    dialog |> Dialogs.update(alice, msg_id, updated_text)
    assert [_, %{type: :text, content: ^updated_text}] = dialog |> Dialogs.read(alice)
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
