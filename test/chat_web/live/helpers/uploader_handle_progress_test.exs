defmodule ChatWeb.Helpers.UploaderHandleProgressTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.ChunkedFiles
  alias Chat.Content.Files
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.Dialogs.PrivateMessage
  alias Chat.Rooms
  alias Chat.Rooms.PlainMessage
  alias Chat.Upload.UploadMetadata
  alias Chat.Utils.StorageId
  alias ChatWeb.LiveHelpers.Uploader
  alias Phoenix.LiveView.UploadEntry

  describe "handle_progress/3" do
    setup [:prepare_view, :open_dialog]

    test "when upload is not finished does nothing", %{view: view} do
      %{entry: entry, socket: socket} = start_upload(%{view: view})
      assert {:noreply, ^socket} = Uploader.handle_progress(:file, entry, socket)
    end

    test "when upload is finished adds the file to the dialog", %{conn: conn, view: view} do
      %{entry: entry, socket: socket} = start_upload(%{view: view})

      %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, entry.uuid)

      entry = %{entry | done?: true, progress: 100}
      assert {:noreply, socket} = Uploader.handle_progress(:file, entry, socket)

      refute Map.get(socket.assigns.uploads_metadata, entry.uuid)

      ChangeTracker.await()

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

      assert %{"url" => file_url} = rendered_image_url(view)

      conn = get(conn, file_url)
      assert conn.status == 200
    end

    test "when upload is finished adds the file to the room", %{conn: conn, view: view} do
      create_and_open_room(%{view: view})

      %{entry: entry, socket: socket} = start_upload(%{view: view})

      %UploadMetadata{} = metadata = Map.get(socket.assigns.uploads_metadata, entry.uuid)

      entry = %{entry | done?: true, progress: 100}
      assert {:noreply, socket} = Uploader.handle_progress(:file, entry, socket)

      refute Map.get(socket.assigns.uploads_metadata, entry.uuid)

      ChangeTracker.await()

      assert [%PlainMessage{} = message] =
               Rooms.read(
                 socket.assigns.room,
                 socket.assigns.room_identity
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

      assert %{"url" => file_url} = rendered_image_url(view)

      conn = get(conn, file_url)
      assert conn.status == 200
    end

    test "when upload is finished starts the next upload", %{view: view} do
      %{entry: %UploadEntry{} = entry_1} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_4, socket: socket} = start_upload(%{view: view})
      socket = Uploader.pause_upload(socket, %{"uuid" => entry_3.uuid})

      entry_1 = %{entry_1 | done?: true, progress: 100}
      assert {:noreply, socket} = Uploader.handle_progress(:file, entry_1, socket)

      refute Map.get(socket.assigns.uploads_metadata, entry_1.uuid)

      assert %UploadMetadata{status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_2.uuid)

      assert %UploadMetadata{status: :paused} =
               Map.get(socket.assigns.uploads_metadata, entry_3.uuid)

      assert %UploadMetadata{status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_4.uuid)
    end
  end

  defp rendered_image_url(view) do
    Regex.named_captures(
      ~r|<img class="object-cover overflow-hidden" src="(?<url>[^"]+)"|,
      render(view)
    )
  end
end
