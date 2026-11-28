defmodule ChatWeb.LiveHelpers.Uploader.Presign do
  @moduledoc """
  External-upload presign step of `ChatWeb.LiveHelpers.Uploader`.

  For a new entry it either reuses an already uploaded file (sends it right away), skips
  a duplicate upload in progress, or registers a chunked upload (resuming an indexed one)
  and returns the `UpChunkUploader` data for the client.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: ChatWeb.Endpoint,
    router: ChatWeb.Router,
    statics: ChatWeb.static_paths()

  import Phoenix.Component, only: [assign: 3]

  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret, FileIndex}

  alias Chat.Upload.{
    Upload,
    UploadIndex,
    UploadKey,
    UploadMetadata,
    UploadStatus,
    UploadSupervisor
  }

  alias ChatWeb.MainLive.Page
  alias Phoenix.LiveView.{Socket, UploadEntry}

  @client_chunk_size div(Application.compile_env(:chat, :file_chunk_size), 1024)
  @max_concurrent_uploads 2

  @type uploader_data ::
          %{skip: true}
          | %{
              chunk_count: integer(),
              chunk_size: integer(),
              entrypoint: String.t(),
              status: atom(),
              uploader: String.t(),
              uuid: String.t()
            }

  @doc "How many uploads may be active at once"
  def max_concurrent_uploads, do: @max_concurrent_uploads

  @spec presign_url(UploadEntry.t(), Socket.t()) :: {:ok, uploader_data(), Socket.t()}
  def presign_url(entry, socket) do
    upload_key = get_upload_key(entry, socket.assigns)

    {uploader_data, socket} =
      cond do
        encrypted_secret = FileIndex.get(reader_hash(socket.assigns), upload_key) ->
          entry = Map.put(entry, :done?, true)

          metadata =
            %UploadMetadata{}
            |> Map.put(:credentials, {upload_key, encrypted_secret})
            |> Map.put(:destination, file_upload_destination(socket.assigns))

          case metadata.destination.type do
            :dialog -> Page.Dialog.send_file(socket, entry, metadata)
            :room -> Page.Room.send_file(socket, entry, metadata)
          end

          {%{skip: true}, socket}

        upload_in_progress?(socket.assigns, upload_key) ->
          {%{skip: true}, socket}

        true ->
          {next_chunk, encrypted_secret} =
            maybe_resume_existing_upload(upload_key, socket.assigns)

          initial_secret = ChunkedFiles.get_file(upload_key)
          ChunkedFilesMultisecret.generate(upload_key, entry.client_size, initial_secret)

          {socket, uploader_data} =
            start_chunked_upload(socket, entry, upload_key, encrypted_secret, next_chunk)

          link =
            ~p"/upload_chunk/#{upload_key |> Base.encode16(case: :lower)}"

          uploader_data = Map.merge(%{entrypoint: link, uuid: entry.uuid}, uploader_data)

          {uploader_data, socket}
      end

    uploader_data = Map.merge(%{uploader: "UpChunkUploader"}, uploader_data)

    {:ok, uploader_data, socket}
  end

  defp get_upload_key(%UploadEntry{} = entry, %{my_id: id} = assigns) do
    assigns
    |> file_upload_destination()
    |> UploadKey.new(id, entry)
  end

  defp reader_hash(%{lobby_mode: :chats, peer: %{pub_key: peer_pub_key}}),
    do: peer_pub_key

  defp reader_hash(%{lobby_mode: :rooms, room: %{pub_key: room_pub_key}}),
    do: room_pub_key

  defp maybe_resume_existing_upload(upload_key, %{me: me} = assigns) do
    case UploadIndex.get(upload_key) do
      nil ->
        encrypted_secret =
          upload_key
          |> ChunkedFiles.new_upload()
          |> ChunkedFiles.encrypt_secret(assigns.me)

        add_upload_to_index(assigns, upload_key, encrypted_secret)
        {0, encrypted_secret}

      %Upload{} = upload ->
        UploadIndex.delete(upload_key)
        secret = upload.encrypted_secret |> ChunkedFiles.decrypt_secret(me)
        ChunkedFiles.resume_upload(upload_key, secret)
        UploadStatus.put(upload_key, :active)
        add_upload_to_index(assigns, upload_key, upload.encrypted_secret)
        next_chunk = ChunkedFiles.next_chunk(upload_key)
        {next_chunk, upload.encrypted_secret}
    end
  end

  defp add_upload_to_index(assigns, key, encrypted_secret) do
    timestamp = Chat.Time.monotonic_to_unix(assigns.monotonic_offset)
    upload = %Upload{encrypted_secret: encrypted_secret, timestamp: timestamp}
    UploadIndex.add(key, upload)
  end

  defp upload_in_progress?(%{uploads_metadata: uploads} = _assigns, upload_key) do
    Enum.any?(uploads, fn {_uuid,
                           %UploadMetadata{
                             credentials: {key, _secret}
                           }} ->
      key == upload_key
    end)
  end

  defp start_chunked_upload(socket, entry, key, secret, next_chunk) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})

    active_uploads =
      uploads
      |> Enum.filter(fn {_uuid, metadata} -> metadata.status == :active end)
      |> length()

    status =
      if active_uploads < @max_concurrent_uploads do
        :active
      else
        :pending
      end

    metadata =
      %UploadMetadata{}
      |> Map.put(:credentials, {key, secret})
      |> Map.put(:destination, file_upload_destination(socket.assigns))
      |> Map.put(:status, status)

    file_uploads_order = socket.assigns.file_uploads_order ++ [entry.uuid]
    uploads_metadata = Map.put(uploads, entry.uuid, metadata)

    uploader_data = %{
      chunk_count: next_chunk,
      chunk_size: @client_chunk_size,
      status: status
    }

    child_spec =
      UploadStatus.child_spec(
        key: key,
        status: if(status == :active, do: :active, else: :inactive)
      )

    DynamicSupervisor.start_child(UploadSupervisor, child_spec)

    {socket
     |> assign(:file_uploads_order, file_uploads_order)
     |> assign(:uploads_metadata, uploads_metadata), uploader_data}
  end

  defp file_upload_destination(%{
         dialog: dialog,
         lobby_mode: :chats,
         peer: %{pub_key: peer_pub_key}
       }),
       do: %{dialog: dialog, pub_key: peer_pub_key |> Base.encode16(case: :lower), type: :dialog}

  defp file_upload_destination(%{lobby_mode: :rooms, room: %{pub_key: room_pub_key}}),
    do: %{pub_key: room_pub_key |> Base.encode16(case: :lower), type: :room}
end
