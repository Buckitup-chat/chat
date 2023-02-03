defmodule ChatWeb.Helpers.UploaderTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest
  import Support.{FakeData, RetryHelper}

  alias Chat.ChunkedFiles
  alias Chat.Dialogs
  alias Chat.Dialogs.{Dialog, PrivateMessage}
  alias Chat.Files
  alias Chat.Rooms
  alias Chat.Rooms.PlainMessage
  alias Chat.Upload.{Upload, UploadIndex, UploadMetadata}
  alias Chat.User
  alias Chat.Utils.StorageId
  alias ChatWeb.LiveHelpers.Uploader
  alias Phoenix.LiveView.{Socket, UploadConfig, UploadEntry, Utils}

  describe "allow_file_upload/3" do
    test "configures file upload" do
      socket = Uploader.allow_file_upload(%Socket{})
      assert %UploadConfig{} = upload_config = socket.assigns.uploads.file

      assert upload_config.accept == :any
      assert upload_config.auto_upload?
      assert upload_config.external == (&Uploader.presign_url/2)
      assert upload_config.max_entries == 2000
      assert upload_config.max_file_size == 102_400_000_000
      assert upload_config.progress_event == (&Uploader.handle_progress/3)
    end

    test "starts 2 concurrent uploads maximum", %{conn: conn} do
      %{view: view} = prepare_view(%{conn: conn})
      open_dialog(%{view: view})

      start_upload(%{view: view})
      start_upload(%{view: view})
      %{socket: socket} = start_upload(%{view: view})

      assert map_size(socket.assigns.uploads_metadata) == 3
      assert length(socket.assigns.uploads.file.entries) == 3

      assert socket.assigns.uploads_metadata
             |> Enum.filter(fn {_uuid, %UploadMetadata{} = metadata} ->
               metadata.status == :active
             end)
             |> length() == 2
    end
  end

  describe "cancel_upload/2" do
    setup [:prepare_view, :open_dialog]

    test "when upload doesn't exist it doesn't crash", %{socket: socket} do
      Uploader.cancel_upload(socket, %{"ref" => "phx-unknownref", "uuid" => UUID.uuid4()})
    end

    test "cancels an upload", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})

      socket = Uploader.cancel_upload(socket, %{"ref" => entry.ref, "uuid" => entry.uuid})

      assert Enum.empty?(socket.assigns.uploads_metadata)
      assert Enum.empty?(socket.assigns.uploads.file.entries)
      assert [push_event | _rest] = Utils.get_push_events(socket)
      assert push_event == ["upload:cancel", %{uuid: entry.uuid}]
    end

    test "starts the next upload", %{view: view} do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_4, socket: socket} = start_upload(%{view: view})

      socket = Uploader.cancel_upload(socket, %{"ref" => entry_1.ref, "uuid" => entry_1.uuid})

      refute Map.get(socket.assigns.uploads_metadata, entry_1.uuid)

      assert %UploadMetadata{status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_2.uuid)

      assert %UploadMetadata{status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_3.uuid)

      assert %UploadMetadata{status: :paused} =
               Map.get(socket.assigns.uploads_metadata, entry_4.uuid)

      uuids =
        socket.assigns.uploads.file.entries
        |> Enum.map(& &1.uuid)
        |> Enum.into(MapSet.new())

      refute MapSet.member?(uuids, entry_1.uuid)
      assert MapSet.member?(uuids, entry_2.uuid)
      assert MapSet.member?(uuids, entry_3.uuid)
      assert MapSet.member?(uuids, entry_4.uuid)
    end
  end

  describe "move_upload/2" do
    setup [:prepare_view, :open_dialog]

    test "when upload doesn't exist it doesn't crash", %{socket: socket} do
      Uploader.move_upload(socket, %{"index" => 0, "uuid" => UUID.uuid4()})
    end

    test "when new index is higher than the number of uploads it doesn't crash", %{
      view: view
    } do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{socket: socket} = start_upload(%{view: view})

      Uploader.move_upload(socket, %{"index" => 10, "uuid" => entry_1.uuid})
    end

    test "moves upload higher", %{view: view} do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3, socket: socket} = start_upload(%{view: view})

      socket = Uploader.move_upload(socket, %{"index" => 0, "uuid" => entry_2.uuid})

      uuids =
        socket.assigns.uploads.file.entries
        |> Enum.map(& &1.uuid)

      assert uuids == [
               entry_2.uuid,
               entry_1.uuid,
               entry_3.uuid
             ]
    end

    test "moves upload lower", %{view: view} do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3, socket: socket} = start_upload(%{view: view})

      socket = Uploader.move_upload(socket, %{"index" => 2, "uuid" => entry_2.uuid})

      uuids =
        socket.assigns.uploads.file.entries
        |> Enum.map(& &1.uuid)

      assert uuids == [
               entry_1.uuid,
               entry_3.uuid,
               entry_2.uuid
             ]
    end

    test "leaves upload in the same place", %{view: view} do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3, socket: socket} = start_upload(%{view: view})

      socket = Uploader.move_upload(socket, %{"index" => 1, "uuid" => entry_2.uuid})

      uuids =
        socket.assigns.uploads.file.entries
        |> Enum.map(& &1.uuid)

      assert uuids == [
               entry_1.uuid,
               entry_2.uuid,
               entry_3.uuid
             ]
    end
  end

  describe "pause_upload/2" do
    setup [:prepare_view, :open_dialog]

    test "when upload doesn't exist it doesn't crash", %{socket: socket} do
      Uploader.pause_upload(socket, %{"uuid" => UUID.uuid4()})
    end

    test "pauses an upload", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})

      socket = Uploader.pause_upload(socket, %{"uuid" => entry.uuid})

      assert %UploadMetadata{} =
               upload_metadata = Map.get(socket.assigns.uploads_metadata, entry.uuid)

      assert upload_metadata.status == :paused
      assert length(socket.assigns.uploads.file.entries) == 1
      assert [push_event | _rest] = Utils.get_push_events(socket)
      assert push_event == ["upload:pause", %{uuid: entry.uuid}]
    end

    test "pausing an already paused upload doesn't crash", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})

      socket = Uploader.pause_upload(socket, %{"uuid" => entry.uuid})
      Uploader.pause_upload(socket, %{"uuid" => entry.uuid})
    end
  end

  describe "resume_upload/2" do
    setup [:prepare_view, :open_dialog]

    test "when upload doesn't exist it doesn't crash", %{socket: socket} do
      Uploader.resume_upload(socket, %{"uuid" => UUID.uuid4()})
    end

    test "resumes an upload", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})

      socket = Uploader.pause_upload(socket, %{"uuid" => entry.uuid})
      socket = Uploader.resume_upload(socket, %{"uuid" => entry.uuid})

      assert %UploadMetadata{} =
               upload_metadata = Map.get(socket.assigns.uploads_metadata, entry.uuid)

      assert upload_metadata.status == :active
      assert length(socket.assigns.uploads.file.entries) == 1
      assert [_pause_event, push_event | _rest] = Utils.get_push_events(socket)
      assert push_event == ["upload:resume", %{uuid: entry.uuid}]
    end

    test "resuming an active upload doesn't crash", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})

      Uploader.resume_upload(socket, %{"uuid" => entry.uuid})
    end
  end

  describe "presign_url/2" do
    setup [:prepare_view, :open_dialog]

    test "returns data for a new dialog file upload", %{socket: socket} do
      old_uploads_index = UploadIndex.list()
      assert Enum.empty?(socket.assigns.uploads_metadata)

      uuid = UUID.uuid4()
      entry = upload_entry(uuid)

      assert {:ok, uploader_data, socket} = Uploader.presign_url(entry, socket)

      assert %{
               chunk_count: 0,
               entrypoint: entrypoint,
               status: :active,
               uploader: "UpChunk",
               uuid: ^uuid
             } = uploader_data

      upload_key =
        entrypoint
        |> String.split("/")
        |> List.last()

      assert entrypoint =~ ~p"/upload_chunk/#{upload_key}"

      refute Map.has_key?(old_uploads_index, upload_key)

      retry_until(1_000, fn ->
        assert %Upload{} = UploadIndex.get(upload_key)
      end)

      assert %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, uuid)
      assert {^upload_key, _secret} = metadata.credentials
      assert %{dialog: %Dialog{}, pub_key: pub_key, type: :dialog} = metadata.destination
      assert metadata.status == :active
      assert pub_key == socket.assigns.peer.pub_key
    end

    test "returns data for a new room file upload", %{view: view} do
      %{socket: socket} = create_and_open_room(%{view: view})

      old_uploads_index = UploadIndex.list()
      assert Enum.empty?(socket.assigns.uploads_metadata)

      uuid = UUID.uuid4()
      entry = upload_entry(uuid)

      assert {:ok, uploader_data, socket} = Uploader.presign_url(entry, socket)

      assert %{
               chunk_count: 0,
               entrypoint: entrypoint,
               status: :active,
               uploader: "UpChunk",
               uuid: ^uuid
             } = uploader_data

      upload_key =
        entrypoint
        |> String.split("/")
        |> List.last()

      assert entrypoint =~ ~p"/upload_chunk/#{upload_key}"

      refute Map.has_key?(old_uploads_index, upload_key)

      retry_until(1_000, fn ->
        assert %Upload{} = UploadIndex.get(upload_key)
      end)

      assert %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, uuid)
      assert {^upload_key, _secret} = metadata.credentials
      assert %{pub_key: pub_key, type: :room} = metadata.destination
      assert metadata.status == :active
      assert pub_key == socket.assigns.room.pub_key
    end

    test "when upload is already in progress commands uploader to skip", %{view: view} do
      %{entry: existing_entry, socket: socket} = start_upload(%{view: view})

      uuid = UUID.uuid4()
      new_entry = Map.put(existing_entry, :uuid, uuid)

      assert {:ok, %{skip: true}, socket} = Uploader.presign_url(new_entry, socket)
      assert %UploadMetadata{} = Map.get(socket.assigns.uploads_metadata, existing_entry.uuid)
      refute Map.get(socket.assigns.uploads_metadata, uuid)
    end

    test "returns data to resume a recently stopped upload", %{view: view} do
      %{entry: existing_entry, socket: socket} = start_upload(%{view: view})

      %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, existing_entry.uuid)
      {upload_key, _secret} = metadata.credentials

      uuid = UUID.uuid4()
      new_entry = Map.put(existing_entry, :uuid, uuid)

      assigns =
        socket.assigns
        |> Map.put(:entries, [])
        |> Map.put(:uploads_metadata, %{})

      socket = Map.put(socket, :assigns, assigns)

      assert {:ok, uploader_data, socket} = Uploader.presign_url(new_entry, socket)

      assert %{
               chunk_count: 0,
               entrypoint: entrypoint,
               status: :active,
               uploader: "UpChunk",
               uuid: ^uuid
             } = uploader_data

      assert entrypoint =~ ~p"/upload_chunk/#{upload_key}"

      assert %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, uuid)
      assert {^upload_key, _secret} = metadata.credentials
      assert metadata.status == :active
    end

    test "when file has already been uploaded to the dialog commands uploader to skip", %{
      view: view
    } do
      %{entry: existing_entry, file: file, filename: filename, socket: socket} =
        start_upload(%{view: view})

      render_upload(file, filename, 100)

      uuid = UUID.uuid4()
      new_entry = Map.put(existing_entry, :uuid, uuid)

      assigns =
        socket.assigns
        |> Map.put(:entries, [])
        |> Map.put(:uploads_metadata, %{})

      socket = Map.put(socket, :assigns, assigns)

      assert {:ok, %{skip: true}, socket} = Uploader.presign_url(new_entry, socket)
      refute Map.get(socket.assigns.uploads_metadata, existing_entry.uuid)
      refute Map.get(socket.assigns.uploads_metadata, uuid)

      retry_until(1_000, fn ->
        assert [%PrivateMessage{} = message_1, %PrivateMessage{} = message_2] =
                 Dialogs.read(socket.assigns.dialog, socket.assigns.me)

        assert message_1.type == :image
        assert {id_1, secret_1} = StorageId.from_json(message_1.content)
        assert message_2.type == :image
        assert {id_2, secret_2} = StorageId.from_json(message_2.content)
        assert Files.get(id_1, secret_1) == Files.get(id_2, secret_2)
      end)
    end

    test "when file has already been uploaded to the room commands uploader to skip", %{
      view: view
    } do
      create_and_open_room(%{view: view})

      %{entry: existing_entry, file: file, filename: filename, socket: socket} =
        start_upload(%{view: view})

      render_upload(file, filename, 100)

      uuid = UUID.uuid4()
      new_entry = Map.put(existing_entry, :uuid, uuid)

      assigns =
        socket.assigns
        |> Map.put(:entries, [])
        |> Map.put(:uploads_metadata, %{})

      socket = Map.put(socket, :assigns, assigns)

      assert {:ok, %{skip: true}, socket} = Uploader.presign_url(new_entry, socket)
      refute Map.get(socket.assigns.uploads_metadata, existing_entry.uuid)
      refute Map.get(socket.assigns.uploads_metadata, uuid)

      retry_until(1_000, fn ->
        assert [%PlainMessage{} = message_1, %PlainMessage{} = message_2] =
                 Rooms.read(
                   socket.assigns.room,
                   socket.assigns.room_identity,
                   &User.id_map_builder/1
                 )

        assert message_1.type == :image
        assert {id_1, secret_1} = StorageId.from_json(message_1.content)
        assert message_2.type == :image
        assert {id_2, secret_2} = StorageId.from_json(message_2.content)
        assert Files.get(id_1, secret_1) == Files.get(id_2, secret_2)
      end)
    end
  end

  describe "handle_progress/3" do
    setup [:prepare_view, :open_dialog]

    test "when upload is not finished does nothing", %{view: view} do
      %{entry: entry, socket: socket} = start_upload(%{view: view})
      assert {:noreply, ^socket} = Uploader.handle_progress(:file, entry, socket)
    end

    test "when upload is finished adds the file to the dialog", %{view: view} do
      %{entry: entry, socket: socket} = start_upload(%{view: view})

      %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, entry.uuid)

      entry = %{entry | done?: true, progress: 100}
      assert {:noreply, socket} = Uploader.handle_progress(:file, entry, socket)

      refute Map.get(socket.assigns.uploads_metadata, entry.uuid)

      retry_until(1_000, fn ->
        assert [%PrivateMessage{} = message] =
                 Dialogs.read(socket.assigns.dialog, socket.assigns.me)

        assert message.type == :image
        assert {id, secret} = StorageId.from_json(message.content)

        assert [chunk_key, encoded_chunk_secret, _, type, filename, size] = Files.get(id, secret)

        assert {^chunk_key, encrypted_secret} = metadata.credentials

        assert Base.decode64!(encoded_chunk_secret) ==
                 ChunkedFiles.decrypt_secret(encrypted_secret, socket.assigns.me)

        assert type == entry.client_type
        assert filename == entry.client_name
        assert size == "#{entry.client_size} b"
      end)
    end

    test "when upload is finished adds the file to the room", %{view: view} do
      create_and_open_room(%{view: view})

      %{entry: entry, socket: socket} = start_upload(%{view: view})

      %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, entry.uuid)

      entry = %{entry | done?: true, progress: 100}
      assert {:noreply, socket} = Uploader.handle_progress(:file, entry, socket)

      refute Map.get(socket.assigns.uploads_metadata, entry.uuid)

      retry_until(1_000, fn ->
        assert [%PlainMessage{} = message] =
                 Rooms.read(
                   socket.assigns.room,
                   socket.assigns.room_identity,
                   &User.id_map_builder/1
                 )

        assert message.type == :image
        assert {id, secret} = StorageId.from_json(message.content)

        assert [chunk_key, encoded_chunk_secret, _, type, filename, size] = Files.get(id, secret)

        assert {^chunk_key, encrypted_secret} = metadata.credentials

        assert Base.decode64!(encoded_chunk_secret) ==
                 ChunkedFiles.decrypt_secret(encrypted_secret, socket.assigns.me)

        assert type == entry.client_type
        assert filename == entry.client_name
        assert size == "#{entry.client_size} b"
      end)
    end

    test "when upload is finished starts the next upload", %{view: view} do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_4, socket: socket} = start_upload(%{view: view})

      entry_1 = %{entry_1 | done?: true, progress: 100}
      assert {:noreply, socket} = Uploader.handle_progress(:file, entry_1, socket)

      refute Map.get(socket.assigns.uploads_metadata, entry_1.uuid)

      assert %UploadMetadata{status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_2.uuid)

      assert %UploadMetadata{status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_3.uuid)

      assert %UploadMetadata{status: :paused} =
               Map.get(socket.assigns.uploads_metadata, entry_4.uuid)
    end
  end
end