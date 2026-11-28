defmodule ChatWeb.LiveHelpers.Uploader do
  @moduledoc """
  LiveView helper handling file upload.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias Chat.ChunkedFiles
  alias Chat.Upload.{UploadIndex, UploadMetadata, UploadStatus}
  alias ChatWeb.LiveHelpers.Uploader.Presign
  alias ChatWeb.MainLive.Page
  alias Phoenix.LiveView.{Socket, UploadEntry}

  @type entry :: UploadEntry.t()
  @type params :: map()
  @type socket :: Socket.t()

  @spec allow_file_upload(socket()) :: socket()
  def allow_file_upload(%Socket{} = socket) do
    socket
    |> allow_upload(:file,
      accept: :any,
      auto_upload: true,
      external: &__MODULE__.presign_url/2,
      max_entries: 2000,
      max_file_size: 102_400_000_000,
      progress: &__MODULE__.handle_progress/3
    )
    |> assign(:file_uploads_order, [])
    |> assign(:uploads_metadata, %{})
  end

  @spec cancel_upload(socket(), params()) :: socket()
  def cancel_upload(%Socket{} = socket, %{"ref" => ref, "uuid" => uuid}) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})

    case Map.get(uploads, uuid) do
      %UploadMetadata{} = metadata ->
        {key, _secret} = metadata.credentials
        UploadStatus.stop(key)
        file_uploads_order = List.delete(socket.assigns.file_uploads_order, uuid)

        socket
        |> assign(:file_uploads_order, file_uploads_order)
        |> assign(:uploads_metadata, Map.delete(uploads, uuid))
        |> cancel_upload(:file, ref)
        |> maybe_resume_next_upload()

      nil ->
        socket
    end
  end

  @spec move_upload(socket(), params()) :: socket()
  def move_upload(%Socket{} = socket, %{"index" => new_index, "uuid" => uuid}) do
    file_uploads_order = socket.assigns.file_uploads_order

    case Enum.find_index(file_uploads_order, &(&1 == uuid)) do
      nil ->
        socket

      old_index ->
        {^uuid, file_uploads_order} = List.pop_at(file_uploads_order, old_index)
        file_uploads_order = List.insert_at(file_uploads_order, new_index, uuid)
        assign(socket, :file_uploads_order, file_uploads_order)
    end
  end

  @spec pause_upload(socket(), params()) :: socket()
  def pause_upload(%Socket{} = socket, %{"uuid" => uuid}) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})

    case Map.get(uploads, uuid) do
      %UploadMetadata{} ->
        metadata = Map.put(uploads[uuid], :status, :paused)

        {key, _secret} = metadata.credentials
        UploadStatus.put(key, :inactive)

        assign(socket, :uploads_metadata, Map.put(uploads, uuid, metadata))
        |> maybe_delete_entries_errors()

      nil ->
        socket
    end
  end

  @spec resume_upload(socket(), params()) :: socket()
  def resume_upload(%Socket{} = socket, %{"uuid" => uuid}) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})

    case Map.get(uploads, uuid) do
      %UploadMetadata{} ->
        metadata = Map.put(uploads[uuid], :status, :active)

        {key, _secret} = metadata.credentials
        UploadStatus.put(key, :active)

        socket
        |> assign(:uploads_metadata, Map.put(uploads, uuid, metadata))
        |> push_event("upload:resume", %{uuid: uuid})

      nil ->
        socket
    end
  end

  defp maybe_delete_entries_errors(%Socket{} = socket) do
    key_path = [:assigns, :uploads, :file, :errors] |> Enum.map(&Access.key!/1)

    socket |> put_in(key_path, [])
  end

  @spec presign_url(entry(), socket()) :: {:ok, Presign.uploader_data(), socket()}
  defdelegate presign_url(entry, socket), to: Presign

  @spec handle_progress(:file, entry(), socket()) :: {:noreply, socket()}
  def handle_progress(
        _name,
        %{progress: 100, uuid: uuid} = entry,
        %{assigns: %{uploads_metadata: uploads}} = socket
      ) do
    %UploadMetadata{} = metadata = uploads[uuid]
    {key, _} = metadata.credentials
    ChunkedFiles.mark_consumed(key)
    UploadIndex.delete(key)

    case metadata.destination.type do
      :dialog -> Page.Dialog.send_file(socket, entry, metadata)
      :room -> Page.Room.send_file(socket, entry, metadata)
    end

    file_uploads_order = List.delete(socket.assigns.file_uploads_order, uuid)

    {:noreply,
     socket
     |> assign(:file_uploads_order, file_uploads_order)
     |> assign(:uploads_metadata, Map.delete(uploads, uuid))
     |> maybe_resume_next_upload()}
  end

  def handle_progress(_name, _entry, socket), do: {:noreply, socket}

  defp maybe_resume_next_upload(%{assigns: %{uploads_metadata: uploads}} = socket) do
    active_uploads =
      uploads
      |> Enum.filter(fn {_uuid, metadata} -> metadata.status == :active end)
      |> length()

    next_uuid =
      Enum.find(socket.assigns.file_uploads_order, fn uuid ->
        case Map.get(uploads, uuid) do
          nil ->
            false

          %UploadMetadata{} = metadata ->
            entry = Enum.find(socket.assigns.uploads.file.entries, &(&1.uuid == uuid))
            entry.valid? and metadata.status == :pending
        end
      end)

    cond do
      active_uploads >= Presign.max_concurrent_uploads() ->
        socket

      is_nil(next_uuid) ->
        socket

      true ->
        resume_upload(socket, %{"uuid" => next_uuid})
    end
  end
end
