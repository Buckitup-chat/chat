defmodule ChatWeb.Helpers.UploaderTest do
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  @moduletag :shared_sandbox

  import ChatWeb.LiveTestHelpers

  alias Chat.Upload.{UploadMetadata, UploadStatus}
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

      statuses =
        socket.assigns.uploads_metadata
        |> Enum.map(fn {_uuid, %UploadMetadata{} = metadata} ->
          {key, _secret} = metadata.credentials
          UploadStatus.get(key)
        end)
        |> Enum.frequencies()

      assert %{active: 2, inactive: 1} = statuses
    end
  end

  describe "cancel_upload/2" do
    setup [:prepare_view, :open_dialog]

    test "when upload doesn't exist it doesn't crash", %{socket: socket} do
      Uploader.cancel_upload(socket, %{"ref" => "phx-unknownref", "uuid" => UUID.uuid4()})
    end

    test "cancels an upload", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})
      {key, _secret} = socket.assigns.uploads_metadata[entry.uuid].credentials

      socket = Uploader.cancel_upload(socket, %{"ref" => entry.ref, "uuid" => entry.uuid})

      assert Enum.empty?(socket.assigns.file_uploads_order)
      assert Enum.empty?(socket.assigns.uploads_metadata)
      assert Enum.empty?(socket.assigns.uploads.file.entries)
      assert catch_exit(UploadStatus.get(key))
    end

    test "starts the next upload", %{view: view} do
      %{entry: %UploadEntry{} = entry_1, socket: socket} = start_upload(%{view: view})
      {key, _secret} = socket.assigns.uploads_metadata[entry_1.uuid].credentials
      %{entry: %UploadEntry{} = entry_2} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_3} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_4} = start_upload(%{view: view})
      %{entry: %UploadEntry{} = entry_5, socket: socket} = start_upload(%{view: view})
      socket = Uploader.pause_upload(socket, %{"uuid" => entry_3.uuid})

      socket = Uploader.cancel_upload(socket, %{"ref" => entry_1.ref, "uuid" => entry_1.uuid})

      refute Map.get(socket.assigns.uploads_metadata, entry_1.uuid)
      assert catch_exit(UploadStatus.get(key))

      assert %UploadMetadata{credentials: {key, _secret}, status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_2.uuid)

      assert UploadStatus.get(key) == :active

      assert %UploadMetadata{credentials: {key, _secret}, status: :paused} =
               Map.get(socket.assigns.uploads_metadata, entry_3.uuid)

      assert UploadStatus.get(key) == :inactive

      assert %UploadMetadata{credentials: {key, _secret}, status: :active} =
               Map.get(socket.assigns.uploads_metadata, entry_4.uuid)

      assert UploadStatus.get(key) == :active

      assert %UploadMetadata{credentials: {key, _secret}, status: :pending} =
               Map.get(socket.assigns.uploads_metadata, entry_5.uuid)

      assert UploadStatus.get(key) == :inactive

      uuids =
        socket.assigns.uploads.file.entries
        |> Enum.map(& &1.uuid)
        |> Enum.into(MapSet.new())

      refute MapSet.member?(uuids, entry_1.uuid)
      assert MapSet.member?(uuids, entry_2.uuid)
      assert MapSet.member?(uuids, entry_3.uuid)
      assert MapSet.member?(uuids, entry_4.uuid)
      assert MapSet.member?(uuids, entry_5.uuid)
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

      assert socket.assigns.file_uploads_order == [
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

      assert socket.assigns.file_uploads_order == [
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

      assert socket.assigns.file_uploads_order == [
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
      {key, _secret} = upload_metadata.credentials
      assert UploadStatus.get(key) == :inactive
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
      assert [push_event | _rest] = Utils.get_push_events(socket)
      assert push_event == ["upload:resume", %{uuid: entry.uuid}]
      {key, _secret} = upload_metadata.credentials
      assert UploadStatus.get(key) == :active
    end

    test "resuming an active upload doesn't crash", %{view: view} do
      %{entry: %UploadEntry{} = entry, socket: socket} = start_upload(%{view: view})

      Uploader.resume_upload(socket, %{"uuid" => entry.uuid})
    end
  end
end
