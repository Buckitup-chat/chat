defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  require Logger
  alias Phoenix.LiveView.JS

  alias Chat.ChunkedFiles
  alias Chat.Rooms
  alias Chat.UploadMetadata
  alias ChatWeb.MainLive.Layout
  alias ChatWeb.MainLive.Page
  alias ChatWeb.Hooks.LocalTimeHook
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
     |> push_event("upload:cancel", %{uuid: uuid})
     |> maybe_resume_next_upload()}
  end

  def handle_event("upload:pause", %{"uuid" => uuid}, socket) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})
    metadata = Map.put(uploads[uuid], :status, :paused)

    {:noreply,
     socket
     |> assign(:uploads_metadata, Map.put(uploads, uuid, metadata))
     |> push_event("upload:pause", %{uuid: uuid})}
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

  def handle_info(:room_request, socket) do
    socket
    |> Page.Lobby.approve_requests()
    |> noreply()
  end

  def handle_info(:room_request_approved, socket) do
    socket
    |> Page.Lobby.join_rooms()
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

  def open_content(%JS{} = js, time \\ 100) do
    js
    |> JS.hide(transition: "fade-out", to: "#navbarTop", time: 0)
    |> JS.hide(transition: "fade-out", to: "#navbarBottom", time: 0)
    |> JS.remove_class("hidden sm:flex",
      transition: "fade-in",
      to: "#contentContainer",
      time: time
    )
    |> JS.add_class("hidden", to: "#chatRoomBar", transition: "fade-out", time: 0)
  end

  def close_content(%JS{} = js, time \\ 100) do
    js
    |> JS.show(transition: "fade-in", to: "#navbarTop", display: "flex", time: time)
    |> JS.show(transition: "fade-in", to: "#navbarBottom", display: "flex", time: time)
    |> JS.add_class("hidden sm:flex", transition: "fade-out", to: "#contentContainer", time: 0)
    |> JS.remove_class("hidden", to: "#chatRoomBar", transition: "fade-in", time: time)
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
    {key, secret} = ChunkedFiles.new_upload()
    {socket, status} = start_chunked_upload(socket, entry, key, secret)
    link = Helpers.upload_chunk_url(ChatWeb.Endpoint, :put, key)

    {:ok, %{uploader: "UpChunk", entrypoint: link, status: status, uuid: entry.uuid}, socket}
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

  defp start_chunked_upload(socket, entry, key, secret) do
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
      |> Map.put(:destination, file_upload_destination(socket))
      |> Map.put(:status, status)

    {assign(socket, :uploads_metadata, Map.put(uploads, entry.uuid, metadata)), status}
  end

  defp file_upload_destination(
         %{assigns: %{dialog: dialog, lobby_mode: :chats, peer: %{pub_key: peer_pub_key}}} =
           _socket
       ),
       do: %{dialog: dialog, pub_key: peer_pub_key, type: :dialog}

  defp file_upload_destination(
         %{assigns: %{lobby_mode: :rooms, room: %{pub_key: room_pub_key} = room}} = _socket
       ),
       do: %{pub_key: room_pub_key, room: room, type: :room}

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
        resume_upload(socket, next_upload_uuid)
    end
  end

  defp resume_upload(socket, uuid) do
    uploads = Map.get(socket.assigns, :uploads_metadata, %{})
    metadata = Map.put(uploads[uuid], :status, :active)

    socket
    |> assign(:uploads_metadata, Map.put(uploads, uuid, metadata))
    |> push_event("upload:resume", %{uuid: uuid})
  end
end
