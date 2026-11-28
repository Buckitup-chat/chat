defmodule ChatWeb.Helpers.UploaderPresignUrlTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest
  import Support.{FakeData, RetryHelper}

  alias Chat.Content.Files
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.Dialogs.{Dialog, PrivateMessage}
  alias Chat.Rooms
  alias Chat.Rooms.PlainMessage
  alias Chat.Upload.{Upload, UploadIndex, UploadMetadata}
  alias Chat.Utils.StorageId
  alias ChatWeb.LiveHelpers.Uploader
  alias ChatWeb.MainLive.Index

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
               chunk_size: 10_240,
               entrypoint: entrypoint,
               status: :active,
               uploader: "UpChunkUploader",
               uuid: ^uuid
             } = uploader_data

      upload_key = upload_key_from(entrypoint)

      assert entrypoint =~ ~p"/upload_chunk/#{Base.encode16(upload_key, case: :lower)}"

      refute Map.has_key?(old_uploads_index, upload_key)

      retry_until(1_000, fn ->
        assert %Upload{} = UploadIndex.get(upload_key)
      end)

      assert %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, uuid)
      assert {^upload_key, _secret} = metadata.credentials
      assert %{dialog: %Dialog{}, pub_key: pub_key, type: :dialog} = metadata.destination
      assert metadata.status == :active
      assert Base.decode16!(pub_key, case: :lower) == socket.assigns.peer.pub_key
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
               chunk_size: 10_240,
               entrypoint: entrypoint,
               status: :active,
               uploader: "UpChunkUploader",
               uuid: ^uuid
             } = uploader_data

      upload_key = upload_key_from(entrypoint)

      assert entrypoint =~ ~p"/upload_chunk/#{Base.encode16(upload_key, case: :lower)}"

      refute Map.has_key?(old_uploads_index, upload_key)

      retry_until(1_000, fn ->
        assert %Upload{} = UploadIndex.get(upload_key)
      end)

      assert %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, uuid)
      assert {^upload_key, _secret} = metadata.credentials
      assert %{pub_key: pub_key, type: :room} = metadata.destination
      assert metadata.status == :active
      assert pub_key |> Base.decode16!(case: :lower) == socket.assigns.room.pub_key
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

      socket = forget_uploads(socket)

      assert {:ok, uploader_data, socket} = Uploader.presign_url(new_entry, socket)

      assert %{
               chunk_count: 0,
               chunk_size: 10_240,
               entrypoint: entrypoint,
               status: :active,
               uploader: "UpChunkUploader",
               uuid: ^uuid
             } = uploader_data

      assert entrypoint =~ ~p"/upload_chunk/#{upload_key |> Base.encode16(case: :lower)}"

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

      socket = forget_uploads(socket)

      assert {:ok, %{skip: true}, socket} = Uploader.presign_url(new_entry, socket)
      refute Map.get(socket.assigns.uploads_metadata, existing_entry.uuid)
      refute Map.get(socket.assigns.uploads_metadata, uuid)

      ChangeTracker.await()

      assert [%PrivateMessage{} = message_1, %PrivateMessage{} = message_2] =
               Dialogs.read(socket.assigns.dialog, socket.assigns.me)

      assert message_1.type == :image
      assert credentials_1 = StorageId.from_json(message_1.content)
      assert message_2.type == :image
      assert credentials_2 = StorageId.from_json(message_2.content)
      assert Files.get(credentials_1) == Files.get(credentials_2)

      state = :sys.get_state(view.pid)
      socket = state.socket

      delete_message(socket, "dialog", message_1)

      ChangeTracker.await()

      assert Files.get(credentials_1)
      assert Files.get(credentials_2)

      delete_message(socket, "dialog", message_2)

      ChangeTracker.await()

      refute Files.get(credentials_1)
      refute Files.get(credentials_2)
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

      socket = forget_uploads(socket)

      assert {:ok, %{skip: true}, socket} = Uploader.presign_url(new_entry, socket)
      refute Map.get(socket.assigns.uploads_metadata, existing_entry.uuid)
      refute Map.get(socket.assigns.uploads_metadata, uuid)

      ChangeTracker.await()

      assert [%PlainMessage{} = message_1, %PlainMessage{} = message_2] =
               Rooms.read(
                 socket.assigns.room,
                 socket.assigns.room_identity
               )

      assert message_1.type == :image
      assert credentials_1 = StorageId.from_json(message_1.content)
      assert message_2.type == :image
      assert credentials_2 = StorageId.from_json(message_2.content)
      assert Files.get(credentials_1) == Files.get(credentials_2)

      state = :sys.get_state(view.pid)
      socket = state.socket

      delete_message(socket, "room", message_1)

      ChangeTracker.await()

      assert Files.get(credentials_1)
      assert Files.get(credentials_2)

      delete_message(socket, "room", message_2)

      ChangeTracker.await()

      refute Files.get(credentials_1)
      refute Files.get(credentials_2)
    end
  end

  defp upload_key_from(entrypoint) do
    entrypoint
    |> String.split("/")
    |> List.last()
    |> Base.decode16!(case: :lower)
  end

  defp forget_uploads(socket) do
    assigns =
      socket.assigns
      |> Map.put(:entries, [])
      |> Map.put(:uploads_metadata, %{})

    Map.put(socket, :assigns, assigns)
  end

  defp delete_message(socket, kind, message) do
    messages = Jason.encode!([%{id: message.id, index: Integer.to_string(message.index)}])
    Index.handle_event("#{kind}/delete-messages", %{"messages" => messages}, socket)
  end
end
