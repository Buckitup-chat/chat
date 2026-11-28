defmodule Chat.Test.KeyScopeFixtures do
  @moduledoc """
  CubDB world for `Chat.Db.Scope.KeyScope.get_keys/2` tests.

  Alice, Bob and Charlie share two dialogs and two rooms. The keys are scoped to Alice
  and the first room, so everything in the Bob ↔ Charlie dialog and the second room
  must stay out.
  """

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
    User
  }

  alias Chat.Db.{ChangeTracker, Scope.KeyScope}
  alias Chat.Utils.StorageId
  alias Support.FakeData

  @doc """
  Named setup: builds the whole world and returns it with `keys` scoped to Alice
  and the first room.
  """
  def build_key_scope_world(_context) do
    %{}
    |> register_users()
    |> fill_dialogs()
    |> fill_first_room()
    |> fill_second_room()
    |> then(
      &Map.put(&1, :keys, KeyScope.get_keys(Chat.Db.db(), [&1.alice_key, &1.first_room_key]))
    )
  end

  @doc "Whether `keys` hold a `kind` message key (`:dialog_message` / `:room_message`) of `message`."
  def has_message_key?(keys, kind, message) do
    hash = message.id |> Enigma.hash()
    Enum.any?(keys, &match?({^kind, _, _, ^hash}, &1))
  end

  @doc "Number of `keys` of `kind` (first tuple element)."
  def kind_count(keys, kind), do: Enum.count(keys, &(kind_of(&1) == kind))

  @doc "Number of `{:chunk_key, {:file_chunk, _, _, _}}` keys."
  def chunk_key_count(keys),
    do: Enum.count(keys, &match?({:chunk_key, {:file_chunk, _, _, _}}, &1))

  defp kind_of({kind, _}), do: kind
  defp kind_of({kind, _, _}), do: kind
  defp kind_of({kind, _, _, _}), do: kind

  defp register_users(world) do
    [alice, bob, charlie] = ~W(Alice Bob Charlie) |> Enum.map(&registered_user/1)

    Map.merge(world, %{
      alice: alice,
      alice_key: Identity.pub_key(alice),
      bob: bob,
      bob_key: Identity.pub_key(bob),
      charlie: charlie,
      charlie_key: Identity.pub_key(charlie)
    })
  end

  defp registered_user(name), do: name |> User.login() |> tap(&User.register/1)

  defp fill_dialogs(%{alice: alice, bob: bob, charlie: charlie} = world) do
    alice_bob = Dialogs.find_or_open(alice, Card.from_identity(bob))
    bob_charlie = Dialogs.find_or_open(bob, Card.from_identity(charlie))
    alice_bob_message = add_dialog_text("Alice welcomes Bob", alice, alice_bob)
    bob_alice_message = add_dialog_text("Bob greets Alice", bob, alice_bob)
    {bob_alice_memo_message, bob_alice_memo_key} = add_dialog_memo(bob, alice_bob)
    bob_charlie_message = add_dialog_text("Bob greets Charlie", bob, bob_charlie)
    {bob_charlie_memo_message, bob_charlie_memo_key} = add_dialog_memo(bob, bob_charlie)

    Map.merge(world, %{
      alice_bob_dialog: alice_bob,
      bob_charlie_dialog: bob_charlie,
      alice_bob_message: alice_bob_message,
      bob_alice_message: bob_alice_message,
      bob_alice_memo_message: bob_alice_memo_message,
      bob_alice_memo_key: bob_alice_memo_key,
      bob_charlie_message: bob_charlie_message,
      bob_charlie_memo_message: bob_charlie_memo_message,
      bob_charlie_memo_key: bob_charlie_memo_key
    })
  end

  defp add_dialog_text(text, author, dialog) do
    {_index, message} = text |> Messages.Text.new(1) |> Dialogs.add_new_message(author, dialog)
    message
  end

  defp add_dialog_memo(author, dialog) do
    {_index, message} =
      indexed =
      "-"
      |> String.duplicate(151)
      |> Messages.Text.new(1)
      |> Dialogs.add_new_message(author, dialog)
      |> MemoIndex.add(dialog, author)

    {message, content_key(dialog, indexed, author)}
  end

  defp content_key(dialog, indexed_message, reader) do
    dialog
    |> Dialogs.read_message(indexed_message, reader)
    |> Map.fetch!(:content)
    |> StorageId.from_json_to_key()
  end

  defp fill_first_room(%{alice: alice, bob: bob, charlie: charlie} = world) do
    {room_identity, room} = Rooms.add(alice, "Alice, Bob and Charlie room", :request)
    room_invite_key = add_room_invite(room_identity, alice, world.alice_bob_dialog)

    ChangeTracker.await()
    join_room(room.pub_key, room_identity, charlie)

    alice_message = add_room_text("Hello first room from Alice", alice, room_identity)
    bob_message = add_room_text("Hello first room from Bob", bob, room_identity)
    charlie_message = add_room_text("Hello first room from Charlie", charlie, room_identity)
    {file_key, image_message} = add_uploaded_image("1.pp", charlie, room_identity, room)

    Map.merge(world, %{
      first_room_key: room.pub_key,
      room_invite_key: room_invite_key,
      alice_first_room_message: alice_message,
      bob_first_room_message: bob_message,
      charlie_first_room_message: charlie_message,
      first_file_key: file_key,
      first_image_message: image_message
    })
  end

  defp add_room_invite(room_identity, author, dialog) do
    room_identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(author, dialog)
    |> RoomInviteIndex.add(dialog, author, Identity.pub_key(room_identity))
    |> then(&content_key(dialog, &1, author))
  end

  defp join_room(room_key, room_identity, user) do
    Rooms.add_request(room_key, user, 1)
    Rooms.approve_request(room_key, Identity.pub_key(user), room_identity, [])
  end

  defp add_room_text(text, author, room_identity) do
    {_index, message} =
      text |> Messages.Text.new(1) |> Rooms.add_new_message(author, room_identity)

    message
  end

  defp fill_second_room(%{bob: bob, charlie: charlie} = world) do
    {room_identity, room} = Rooms.add(bob, "Bob and Charlie room")
    Rooms.Registry.await_saved(room.pub_key)
    join_room(room.pub_key, room_identity, charlie)

    bob_message = add_room_text("Hello second room from Bob", bob, room_identity)
    charlie_message = add_room_text("Hello second room from Charlie", charlie, room_identity)
    {file_key, image_message} = add_uploaded_image("2.pp", charlie, room_identity, room)

    Map.merge(world, %{
      second_room_key: room.pub_key,
      bob_second_room_message: bob_message,
      charlie_second_room_message: charlie_message,
      second_file_key: file_key,
      second_image_message: image_message
    })
  end

  defp add_uploaded_image(name, author, room_identity, room) do
    %Messages.File{data: [file_key, encoded_chunk_secret | _]} = image = FakeData.image(name)

    {_index, message} =
      image |> Map.put(:timestamp, 4) |> Rooms.add_new_message(author, room_identity)

    FileIndex.save(file_key, room.pub_key, message.id, Base.decode64!(encoded_chunk_secret))
    upload_two_chunks(file_key)

    {file_key, message}
  end

  defp upload_two_chunks(file_key) do
    ChunkedFiles.new_upload(file_key)
    ChunkedFiles.save_upload_chunk(file_key, {0, 17}, 30, "some part of info ")
    ChunkedFiles.save_upload_chunk(file_key, {18, 29}, 30, "another part")
  end
end
