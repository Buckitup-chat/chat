defmodule Chat.Db.Scope.CargoKeyScopeTest do
  use ExUnit.Case, async: false

  alias Chat.Db.Scope.KeyScope
  alias Chat.Dialogs
  alias Chat.Identity
  alias Chat.Messages
  alias Chat.RoomInviteIndex
  alias Chat.Rooms
  alias Chat.User

  test "room and invitations in dialogs should be selected" do
    {bot_key, room_key} = generate_user_with_dialogs_content_and_invite_in_room()

    Process.sleep(100)

    # Chat.Db.db()
    # |> CubDB.select()
    # |> Stream.map(fn {k, _} -> k end)
    # |> Enum.to_list()
    # |> Enum.frequencies_by(&elem(&1, 0))
    # |> IO.inspect(label: "db", pretty: true)

    keys = KeyScope.get_cargo_keys(Chat.Db.db(), room_key, [bot_key])

    assert %{dialog_message: 1, dialogs: 1, room_invite: 1, room_invite_index: 1, rooms: 1} ==
             keys
             |> MapSet.to_list()
             |> Enum.frequencies_by(&elem(&1, 0))
             |> Map.drop([:users])
  end

  defp generate_user_with_dialogs_content_and_invite_in_room do
    user = User.login("Alice")
    User.register(user)

    bot = User.login("Bob")
    User.register(bot)
    bot_key = Identity.pub_key(bot)

    {room_identity, _room} = Rooms.add(user, "Room")
    room_key = Identity.pub_key(room_identity)

    dialog = Dialogs.find_or_open(user, bot |> Chat.Card.from_identity())

    "hi"
    |> Messages.Text.new(DateTime.utc_now())
    |> Dialogs.add_new_message(user, dialog)

    room_identity
    |> Messages.RoomInvite.new()
    |> Dialogs.add_new_message(user, dialog)
    |> RoomInviteIndex.add(dialog, user)

    {bot_key, room_key}
  end
end
