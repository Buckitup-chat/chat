defmodule NailveApi.NetworkSyncTest do
  use ExUnit.Case, async: true

  alias Support.FakeData

  test "all keys serialization" do
    %{}
    |> make_all_possible_types_of_data()
    |> assert_no_keys_lost_after_serialization()
    |> assert_deserialized_correctly()
  end

  defp make_all_possible_types_of_data(context) do
    context
    |> Map.put(:data, generate_data())
  end

  defp assert_no_keys_lost_after_serialization(%{data: data} = context) do
    initial_set = data |> Map.keys() |> MapSet.new()
    assert {:ok, serialized_keys} = NaiveApi.Data.all_keys(:params, :api_context)

    received_keys =
      serialized_keys
      |> Enum.map(&NaiveApi.Data.deserialize_key/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    assert initial_set |> MapSet.subset?(received_keys)

    context
    |> Map.put(:received_keys, received_keys)
  end

  defp assert_deserialized_correctly(%{data: data, received_keys: received_keys} = context) do
    received =
      received_keys
      |> Enum.map(fn key ->
        serialized_key = NaiveApi.Data.serialize_key(key)
        assert {:ok, value} = NaiveApi.Data.get_value(%{key: serialized_key}, :api_context)

        {key, value |> NaiveApi.Data.deserialize_value()}
      end)
      |> Map.new()

    Enum.each(data, fn {key, value} ->
      assert received[key] == value,
             "#{inspect(key)}\n#{received[key] |> inspect}\n!=\n#{value |> inspect}"
    end)

    # --- remove ---
    Enum.each(received, fn {key, value} ->
      assert data[key] == value, inspect(key)
    end)

    context
  end

  defp generate_data do
    {alice_key, alice} = make_user("network_sync_Alice")
    {bob_key, bob} = make_user("network_sync_Bob")

    [
      {:users, alice_key},
      {:users, bob_key},
      send_file_in_dialog(from: alice, to: bob),
      send_memo_in_room_w_invitation(from: bob, to: alice),
      log_visit(alice)
    ]
    |> List.flatten()
    |> tap(&Chat.Db.Copying.await_written_into(&1, Chat.Db.db()))
    |> Enum.map(&{&1, Chat.db_get(&1)})
    |> Map.new()
  end

  defp make_user(name) do
    identity = Chat.User.login(name)
    key = Chat.User.register(identity)

    {key, identity}
  end

  defp send_file_in_dialog(from: sender, to: recipient) do
    dialog = Chat.Dialogs.find_or_open(sender, recipient |> Chat.Card.from_identity())
    dialog_key = dialog |> Chat.Dialogs.key()

    file = FakeData.file()
    [file_key, enc_secret | _] = file.data
    {index, msg} = Chat.Dialogs.add_new_message(file, sender, dialog)

    [sender, recipient]
    |> Enum.each(
      &Chat.FileIndex.save(
        file_key,
        &1 |> Chat.Identity.pub_key(),
        msg.id,
        enc_secret |> Base.decode64!()
      )
    )

    Chat.ChunkedFiles.new_upload(file_key)
    Chat.ChunkedFiles.save_upload_chunk(file_key, {0, 29}, 30, "some part of info another part")

    [
      {:dialogs, dialog_key},
      {:file, file.data |> List.first()},
      {:dialog_message, dialog_key, index, msg.id |> Enigma.hash()},
      {:chunk_key, {:file_chunk, file_key, 0, 29}},
      {:file_chunk, file_key, 0, 29},
      {:file_index, sender |> Chat.Identity.pub_key(), file_key, msg.id},
      {:file_index, recipient |> Chat.Identity.pub_key(), file_key, msg.id}
    ]
  end

  defp send_memo_in_room_w_invitation(from: sender, to: recipient) do
    {room_identity, room} = Chat.Rooms.add(sender, "API data request", :request)
    room_key = room_identity |> Chat.Identity.pub_key()
    dialog = Chat.Dialogs.find_or_open(sender, recipient |> Chat.Card.from_identity())
    dialog_key = dialog |> Chat.Dialogs.key()

    room_invite =
      {invite_index, invite_msg} =
      room_identity
      |> Chat.Messages.RoomInvite.new()
      |> Chat.Dialogs.add_new_message(sender, dialog)
      |> Chat.RoomInviteIndex.add(dialog, sender)

    room_invite_key =
      Chat.Dialogs.read_message(dialog, room_invite, sender)
      |> Map.fetch!(:content)
      |> Chat.Utils.StorageId.from_json_to_key()

    {memo_index, memo_msg} =
      msg =
      "-"
      |> String.duplicate(151)
      |> Chat.Messages.Text.new(1)
      |> Chat.Rooms.add_new_message(sender, room_key)
      |> Chat.MemoIndex.add(room, room_identity)

    memo_key =
      Chat.Rooms.read_message(msg, room_identity)
      |> Map.fetch!(:content)
      |> Chat.Utils.StorageId.from_json_to_key()

    [
      {:dialogs, dialog_key},
      {:room_invite, room_invite_key},
      {:rooms, room_key},
      {:room_invite_index, sender |> Chat.Identity.pub_key(), room_invite_key},
      {:room_invite_index, recipient |> Chat.Identity.pub_key(), room_invite_key},
      {:dialog_message, dialog_key, invite_index, invite_msg.id |> Enigma.hash()},
      {:memo, memo_key},
      {:memo_index, room_key, memo_key},
      {:room_message, room_key, memo_index, memo_msg.id |> Enigma.hash()},
    ]
  end

  defp log_visit(identity) do
    Chat.Log.visit(identity, 1)
    index = Chat.Ordering.last({:action_log})

    [
      {:action_log, index, identity |> Chat.Identity.pub_key()}
    ]
  end
end
