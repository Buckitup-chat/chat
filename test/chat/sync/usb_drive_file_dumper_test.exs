defmodule Chat.Sync.UsbDriveFileDumperTest do
  use ExUnit.Case, async: false

  alias Chat.{ChunkedFiles, ChunkedFilesBroker}
  alias Chat.Content.Files
  alias Chat.{Rooms, User}
  alias Chat.Rooms.{Message, PlainMessage, Room}
  alias Chat.Sync.{UsbDriveDumpFile, UsbDriveDumpProgress, UsbDriveDumpRoom, UsbDriveFileDumper}
  alias Chat.Utils.StorageId
  alias Phoenix.PubSub

  describe "dump/2" do
    setup do
      UsbDriveDumpRoom.remove()

      on_exit(fn ->
        File.rm("usb_drive_dump_test_file.JPG")
      end)
    end

    test "saves file as a room message" do
      alice = User.login("Alice")
      User.register(alice)

      {room_identity, %Room{pub_key: room_key} = room} = Rooms.add(alice, "Alice's Room", :public)

      topic =
        room_key
        |> Base.encode16(case: :lower)
        |> then(&"room:#{&1}")

      PubSub.subscribe(Chat.PubSub, topic)
      PubSub.subscribe(Chat.PubSub, "chat::usb_drive_dump_progress")

      File.write!("usb_drive_dump_test_file.JPG", String.duplicate("a", 10_000))

      file = %UsbDriveDumpFile{
        datetime: ~N[2023-04-10 20:00:00],
        name: "usb_drive_dump_test_file.JPG",
        path: "usb_drive_dump_test_file.JPG",
        size: 10_000
      }

      room_key = room.pub_key

      monotonic_offset =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> Chat.Time.monotonic_offset()

      UsbDriveDumpRoom.activate(room_key, room_identity, monotonic_offset)
      UsbDriveDumpRoom.dump()
      UsbDriveDumpRoom.set_total(1, file.size)

      UsbDriveFileDumper.dump(file, 1, room_key, room_identity, monotonic_offset)

      assert_receive {:update_usb_drive_dump_progress,
                      %UsbDriveDumpRoom{
                        identity: ^room_identity,
                        progress: %UsbDriveDumpProgress{
                          percentage: 100,
                          completed_size: 10_000,
                          current_file: 1,
                          current_filename: "usb_drive_dump_test_file.JPG",
                          total_files: 1,
                          total_size: 10_000
                        },
                        pub_key: ^room_key,
                        status: :dumping
                      }}

      assert_receive {:room,
                      {:new_message,
                       {index,
                        %Message{
                          id: id,
                          timestamp: 1_681_156_800,
                          author_key: ^room_key,
                          type: :image
                        }}}},
                     10_000

      assert [
               %PlainMessage{
                 content: content,
                 id: ^id,
                 index: ^index,
                 timestamp: 1_681_156_800,
                 author_key: ^room_key,
                 type: :image
               }
             ] = Rooms.read(room, room_identity)

      assert [file_key, _, _, _, _, _] =
               content
               |> StorageId.from_json()
               |> Files.get()

      file_secret = ChunkedFilesBroker.get(file_key)

      assert ChunkedFiles.chunk_with_byterange({file_key, file_secret}, {0, file.size - 1})
      assert ChunkedFiles.read({file_key, file_secret}) == String.duplicate("a", 10_000)

      UsbDriveDumpRoom.remove()
      UsbDriveDumpRoom.activate(room_key, room_identity, monotonic_offset)
      UsbDriveDumpRoom.dump()
      UsbDriveDumpRoom.set_total(1, file.size)

      UsbDriveFileDumper.dump(file, 1, room_key, room_identity, monotonic_offset)

      assert_receive {:update_usb_drive_dump_progress,
                      %UsbDriveDumpRoom{
                        identity: ^room_identity,
                        progress: %UsbDriveDumpProgress{
                          percentage: 100,
                          completed_size: 10_000,
                          current_file: 1,
                          current_filename: "usb_drive_dump_test_file.JPG",
                          total_files: 1,
                          total_size: 10_000
                        },
                        pub_key: ^room_key,
                        status: :dumping
                      }}

      assert_receive {:room,
                      {:new_message,
                       {new_message_index,
                        %Message{
                          id: new_message_id,
                          timestamp: 1_681_156_800,
                          author_key: ^room_key,
                          type: :image
                        }}}},
                     10_000

      assert [
               %PlainMessage{
                 content: content,
                 id: ^id,
                 index: ^index,
                 timestamp: 1_681_156_800,
                 author_key: ^room_key,
                 type: :image
               },
               %PlainMessage{
                 content: content,
                 id: ^new_message_id,
                 index: ^new_message_index,
                 timestamp: 1_681_156_800,
                 author_key: ^room_key,
                 type: :image
               }
             ] = Rooms.read(room, room_identity)

      assert [^file_key, _, _, _, _, _] =
               content
               |> StorageId.from_json()
               |> Files.get()
    end
  end
end
