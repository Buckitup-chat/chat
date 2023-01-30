defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  require Logger

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.UploadEntry

  alias Chat.ChunkedFiles
  alias Chat.FileIndex
  alias Chat.Upload.{Upload, UploadIndex, UploadMetadata}
  alias Chat.Utils

  alias ChatWeb.Hooks.LocalTimeHook
  alias ChatWeb.MainLive.Layout
  alias ChatWeb.MainLive.Page
  alias ChatWeb.Router.Helpers

  @max_concurrent_uploads 2

  on_mount LocalTimeHook

  @impl true
  def mount(
        params,
        %{"operating_system" => operating_system},
        %{assigns: %{live_action: action}} = socket
      ) do
    Process.flag(:sensitive, true)

    socket = assign(socket, :operating_system, operating_system)

    if connected?(socket) do
      if action == :export do
        socket
        |> assign(:need_login, false)
        |> Page.ExportKeyRing.init(params["id"])
        |> Page.Login.check_stored()
        |> ok()
      else
        socket
        |> assign(
          need_login: true,
          mode: :user_list,
          monotonic_offset: 0
        )
        |> LocalTimeHook.assign_time(Phoenix.LiveView.get_connect_params(socket)["tz_info"])
        |> allow_any500m_upload(:my_keys_file)
        |> allow_file_upload()
        |> Page.Login.check_stored()
        |> ok()
      end
    else
      socket
      |> ok()
    end
  end

  @impl true
  def handle_event("login", %{"login" => %{"name" => name}}, socket) do
    socket
    |> Page.Login.create_user(name)
    |> Page.Lobby.init()
    |> Page.Dialog.init()
    |> Page.Logout.init()
    |> noreply()
  end

  def handle_event("restoreAuth", nil, socket) do
    socket |> noreply()
  end

  def handle_event("restoreAuth", data, %{assigns: %{live_action: :export}} = socket) do
    socket
    |> Page.Login.load_user(data)
    |> noreply()
  end

  def handle_event("restoreAuth", data, socket) do
    socket
    |> Page.Login.load_user(data)
    |> Page.Lobby.init()
    |> Page.Dialog.init()
    |> Page.Logout.init()
    |> noreply()
  end

  def handle_event("client-timestamp", %{"timestamp" => timestamp}, socket) do
    socket
    |> assign(:monotonic_offset, timestamp |> Chat.Time.monotonic_offset())
    |> noreply()
  end

  def handle_event("login:request-key-ring", _, socket) do
    socket
    |> Page.Login.close()
    |> Page.ImportKeyRing.init()
    |> noreply()
  end

  def handle_event("login:import-own-key-ring", _, socket) do
    socket
    |> Page.Login.close()
    |> Page.ImportOwnKeyRing.init()
    |> noreply()
  end

  def handle_event("login:my-keys-file-submit", _, socket) do
    socket |> noreply()
  end

  def handle_event(
        "login:import-own-keyring-decrypt",
        %{"import_own_keyring_password" => %{"password" => password}},
        socket
      ) do
    socket
    |> Page.ImportOwnKeyRing.try_password(password)
    |> noreply()
  end

  def handle_event("login:import-own-keyring-reupload", _, socket) do
    socket
    |> Page.ImportOwnKeyRing.back_to_file()
    |> noreply()
  end

  def handle_event("login:import-own-keyring:drop-password-error", _, socket) do
    socket
    |> Page.ImportOwnKeyRing.drop_error()
    |> noreply()
  end

  def handle_event("login:import-keyring-close", _, socket) do
    socket
    |> Page.ImportKeyRing.close()
    |> assign(:need_login, true)
    |> noreply()
  end

  def handle_event("login:import-own-keyring-close", _, socket) do
    socket
    |> Page.ImportOwnKeyRing.close()
    |> assign(:need_login, true)
    |> noreply()
  end

  def handle_event("login:export-code-close", _, socket) do
    socket
    |> push_event("chat:redirect", %{url: Routes.main_index_path(socket, :index)})
    |> noreply()
  end

  def handle_event("switch-lobby-mode", %{"lobby-mode" => mode}, socket) do
    socket
    |> Page.Lobby.switch_lobby_mode(mode)
    |> Page.Room.init()
    |> noreply()
  end

  def handle_event("chat:load-more", _, %{assigns: %{dialog: %{}}} = socket) do
    socket
    |> Page.Dialog.load_more_messages()
    |> noreply()
  end

  def handle_event("chat:load-more", _, %{assigns: %{room: %{}}} = socket) do
    socket
    |> Page.Room.load_more_messages()
    |> noreply()
  end

  def handle_event("export-keys", %{"export_key_ring" => %{"code" => code}}, socket) do
    socket
    |> Page.ExportKeyRing.send_key_ring(code |> String.to_integer())
    |> noreply
  end

  def handle_event("feed-more", _, socket) do
    socket
    |> Page.Feed.more()
    |> noreply()
  end

  def handle_event("close-feeds", _, socket) do
    socket
    |> Page.Feed.close()
    |> noreply()
  end

  def handle_event("open-data-restore", _, socket) do
    socket
    |> assign(:mode, :restore_data)
    |> noreply()
  end

  def handle_event("backup-file-submit", _, socket), do: socket |> noreply()

  def handle_event("close-data-restore", _, socket) do
    socket
    |> assign(:mode, :lobby)
    |> noreply()
  end

  def handle_event("logout-open", _, socket) do
    socket
    |> Page.Logout.open()
    |> noreply()
  end

  def handle_event("logout-go-middle", _, socket) do
    socket
    |> Page.Logout.go_middle()
    |> noreply()
  end

  def handle_event("logout:toggle-password-visibility", _, socket) do
    socket
    |> Page.Logout.toggle_password_visibility()
    |> noreply()
  end

  def handle_event("logout:toggle-password-confirmation-visibility", _, socket) do
    socket
    |> Page.Logout.toggle_password_confirmation_visibility()
    |> noreply()
  end

  def handle_event("logout-download-insecure", _, socket) do
    socket
    |> Page.Logout.generate_backup("")
    |> Page.Logout.go_final()
    |> noreply()
  end

  def handle_event(
        "logout-download-with-password",
        %{"logout" => form},
        socket
      ) do
    socket
    |> Page.Logout.download_on_good_password(form)
    |> noreply()
  end

  def handle_event("logout-check-password", %{"logout" => form}, socket) do
    socket
    |> Page.Logout.check_password(form)
    |> noreply()
  end

  def handle_event("logout-wipe", _, socket) do
    socket
    |> Page.Login.clear()
    |> Page.Logout.wipe()
    |> noreply()
  end

  def handle_event("logout-close", _, socket) do
    socket
    |> Page.Logout.close()
    |> noreply()
  end

  def handle_event("dialog/" <> event, params, socket) do
    socket
    |> Page.DialogRouter.event({event, params})
    |> noreply()
  end

  def handle_event("room/" <> event, params, socket) do
    socket
    |> Page.RoomRouter.event({event, params})
    |> noreply()
  end

  def handle_event("admin/" <> event, params, socket) do
    socket
    |> Page.AdminPanelRouter.event({event, params})
    |> noreply()
  end

  def handle_event("upload:cancel", %{"ref" => ref, "uuid" => uuid}, socket) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})

    {:noreply,
     socket
     |> assign(:uploads_metadata, Map.delete(uploads, uuid))
     |> cancel_upload(:file, ref)
     |> maybe_resume_next_upload()}
  end

  def handle_event("upload:pause", %{"uuid" => uuid}, socket) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})
    metadata = Map.put(uploads[uuid], :status, :paused)

    {:noreply, assign(socket, :uploads_metadata, Map.put(uploads, uuid, metadata))}
  end

  def handle_event("upload:resume", %{"uuid" => uuid}, socket) do
    {:noreply, resume_upload(socket, uuid)}
  end

  @impl true
  def handle_info({:new_user, card}, socket) do
    socket
    |> Page.Lobby.show_new_user(card)
    |> noreply()
  end

  def handle_info({:new_room, card}, socket) do
    socket
    |> Page.Lobby.show_new_room(card)
    |> noreply()
  end

  def handle_info({:room_request, room_hash, user_hash}, socket) do
    socket
    |> Page.Lobby.approve_room_request(room_hash, user_hash)
    |> noreply()
  end

  def handle_info({:room_request_approved, encrypted_room_entity, user_hash}, socket) do
    socket
    |> Page.Lobby.join_approved_room(encrypted_room_entity, user_hash)
    |> noreply()
  end

  def handle_info({:exported_key_ring, keys}, socket) do
    socket
    |> Page.ImportKeyRing.save_key_ring(keys)
    |> Page.Login.store()
    |> Page.ImportKeyRing.close()
    |> Page.Lobby.init()
    |> Page.Logout.init()
    |> Page.Dialog.init()
    |> noreply()
  end

  def handle_info({:db_status, msg}, socket),
    do: socket |> Page.Lobby.set_db_status(msg) |> noreply()

  def handle_info({:room, msg}, socket),
    do: socket |> Page.RoomRouter.info(msg) |> noreply()

  def handle_info({:platform_response, msg}, socket),
    do: socket |> Page.AdminPanelRouter.info(msg) |> noreply()

  def handle_info({:dialog, msg}, socket), do: socket |> Page.DialogRouter.info(msg) |> noreply()

  def handle_info({ref, :ok}, socket) do
    Process.demonitor(ref, [:flush])

    socket |> noreply()
  end

  def handle_info({ref, {:error, task, _reason}}, socket) do
    Process.demonitor(ref, [:flush])

    socket
    |> Page.Lobby.process(task)
    |> noreply()
  end

  def handle_progress(:my_keys_file, %{done?: true}, socket) do
    socket
    |> Page.ImportOwnKeyRing.read_file()
    |> noreply()
  end

  def handle_progress(_file, _entry, socket) do
    socket |> noreply()
  end

  defp action_confirmation_popup(assigns) do
    ~H"""
    <.modal id={@id} class="">
      <h1 class="text-base font-bold text-grayscale"><%= @title %></h1>
      <p class="mt-3 text-sm text-black/50"><%= @description %></p>
      <div class="mt-5 flex items-center justify-between">
        <button phx-click={hide_modal(@id)} class="w-full mr-1 h-12 border rounded-lg border-black/10">
          Cancel
        </button>
        <button class="confirmButton w-full ml-1 h-12 border-0 rounded-lg bg-grayscale text-white flex items-center justify-center">
          Confirm
        </button>
      </div>
    </.modal>
    """
  end

  def message_of(%{author_hash: _}), do: "room"
  def message_of(_), do: "dialog"

  defp allow_any500m_upload(socket, type, opts \\ []) do
    socket
    |> allow_upload(type,
      auto_upload: true,
      max_file_size: 1_024_000_000,
      accept: :any,
      max_entries: Keyword.get(opts, :max_entries, 1),
      progress: &handle_progress/3
    )
  end

  defp allow_file_upload(socket) do
    socket
    |> allow_upload(:file,
      accept: :any,
      auto_upload: true,
      external: &chunked_presign_url/2,
      max_entries: 2000,
      max_file_size: 102_400_000_000,
      progress: &handle_chunked_progress/3
    )
    |> assign(:uploads_metadata, %{})
  end

  def chunked_presign_url(entry, socket) do
    upload_key = get_upload_key(entry, socket.assigns)

    {uploader_data, socket} =
      cond do
        secret = FileIndex.get(reader_hash(socket.assigns), upload_key) ->
          entry = Map.put(entry, :done?, true)

          metadata =
            %UploadMetadata{}
            |> Map.put(:credentials, {upload_key, secret})
            |> Map.put(:destination, file_upload_destination(socket.assigns))

          case metadata.destination.type do
            :dialog -> Page.Dialog.send_file(socket, entry, metadata)
            :room -> Page.Room.send_file(socket, entry, metadata)
          end

          {%{skip: true}, socket}

        upload_in_progress?(socket.assigns, upload_key) ->
          {%{skip: true}, socket}

        true ->
          {next_chunk, secret} = maybe_resume_existing_upload(upload_key, socket.assigns)

          {socket, uploader_data} =
            start_chunked_upload(socket, entry, upload_key, secret, next_chunk)

          link = Helpers.upload_chunk_url(ChatWeb.Endpoint, :put, upload_key)

          uploader_data = Map.merge(%{entrypoint: link, uuid: entry.uuid}, uploader_data)

          {uploader_data, socket}
      end

    uploader_data = Map.merge(%{uploader: "UpChunk"}, uploader_data)

    {:ok, uploader_data, socket}
  end

  defp get_upload_key(%UploadEntry{} = entry, %{my_id: id} = assigns) do
    destination =
      assigns
      |> file_upload_destination()
      |> Jason.encode!()
      |> Base.encode64()

    [
      id,
      destination,
      entry.client_relative_path,
      entry.client_name,
      entry.client_type,
      entry.client_size,
      entry.client_last_modified
    ]
    |> Enum.join(":")
    |> Utils.hash()
  end

  defp reader_hash(%{lobby_mode: :chats, peer: %{pub_key: peer_pub_key}}),
    do: Utils.hash(peer_pub_key)

  defp reader_hash(%{lobby_mode: :rooms, room: %{pub_key: room_pub_key}}),
    do: Utils.hash(room_pub_key)

  defp maybe_resume_existing_upload(upload_key, assigns) do
    case UploadIndex.get(upload_key) do
      nil ->
        secret =
          upload_key
          |> ChunkedFiles.new_upload()
          |> ChunkedFiles.encrypt_secret(assigns.me)

        add_upload_to_index(assigns, upload_key, secret)
        {0, secret}

      %Upload{} = upload ->
        UploadIndex.delete(upload_key)
        add_upload_to_index(assigns, upload_key, upload.secret)
        next_chunk = ChunkedFiles.next_chunk(upload_key)
        {next_chunk, upload.secret}
    end
  end

  defp add_upload_to_index(assigns, key, secret) do
    timestamp = Chat.Time.monotonic_to_unix(assigns.monotonic_offset)
    upload = %Upload{secret: secret, timestamp: timestamp}
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

  def handle_chunked_progress(
        _name,
        %{progress: 100, uuid: uuid} = entry,
        %{assigns: %{uploads_metadata: uploads}} = socket
      ) do
    "[upload] finalizing" |> Logger.warn()
    %UploadMetadata{} = metadata = uploads[uuid]
    {key, _} = metadata.credentials
    ChunkedFiles.mark_consumed(key)
    UploadIndex.delete(key)

    "[upload] marked consumed" |> Logger.warn()

    case metadata.destination.type do
      :dialog -> Page.Dialog.send_file(socket, entry, metadata)
      :room -> Page.Room.send_file(socket, entry, metadata)
    end

    "[upload] message sent" |> Logger.warn()

    socket
    |> assign(:uploads_metadata, Map.delete(uploads, uuid))
    |> maybe_resume_next_upload()
    |> noreply()
    |> tap(fn _ -> "[upload] done" |> Logger.warn() end)
  end

  def handle_chunked_progress(_name, _entry, socket), do: noreply(socket)

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
        :paused
      end

    metadata =
      %UploadMetadata{}
      |> Map.put(:credentials, {key, secret})
      |> Map.put(:destination, file_upload_destination(socket.assigns))
      |> Map.put(:status, status)

    uploader_data = %{
      chunk_count: next_chunk,
      status: status
    }

    {assign(socket, :uploads_metadata, Map.put(uploads, entry.uuid, metadata)), uploader_data}
  end

  defp file_upload_destination(%{
         dialog: dialog,
         lobby_mode: :chats,
         peer: %{pub_key: peer_pub_key}
       }),
       do: %{dialog: dialog, pub_key: peer_pub_key, type: :dialog}

  defp file_upload_destination(%{lobby_mode: :rooms, room: %{pub_key: room_pub_key}}),
    do: %{pub_key: room_pub_key, type: :room}

  defp maybe_resume_next_upload(%{assigns: %{uploads_metadata: uploads}} = socket) do
    active_uploads =
      uploads
      |> Enum.filter(fn {_uuid, metadata} -> metadata.status == :active end)
      |> length()

    next_upload = Enum.find(uploads, fn {_uuid, metadata} -> metadata.status == :paused end)

    cond do
      active_uploads >= @max_concurrent_uploads ->
        socket

      is_nil(next_upload) ->
        socket

      true ->
        {next_upload_uuid, _metadata} = next_upload

        socket
        |> resume_upload(next_upload_uuid)
        |> push_event("upload:resume", %{uuid: next_upload_uuid})
    end
  end

  defp resume_upload(socket, uuid) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})
    metadata = Map.put(uploads[uuid], :status, :active)

    assign(socket, :uploads_metadata, Map.put(uploads, uuid, metadata))
  end
end
