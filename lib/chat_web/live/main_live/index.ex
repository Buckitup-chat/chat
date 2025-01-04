defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  require Logger

  alias Chat.Admin.CargoSettings
  alias Chat.{AdminRoom, Dialogs, Identity, Messages, RoomInviteIndex}
  alias Chat.Rooms.Room
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}
  alias ChatWeb.Hooks.{LiveModalHook, LocalTimeHook, UploaderHook}

  alias ChatWeb.MainLive.Admin.{
    BackupSettingsForm,
    CargoCameraSensorsForm,
    CargoCheckpointsForm,
    CargoUserData,
    CargoWeightSensorForm,
    FirmwareUpgradeForm,
    LanSettings,
    MediaSettingsForm,
    NetworkSourceList,
    PrivacyPolicy,
    UserSettings,
    ZerotierSettings
  }

  alias ChatWeb.MainLive.{Layout, Page}
  alias ChatWeb.MainLive.Page.RoomForm
  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub

  on_mount LiveModalHook
  on_mount LocalTimeHook
  on_mount UploaderHook

  embed_templates "*"

  @impl true
  def mount(
        params,
        %{"operating_system" => operating_system},
        %{assigns: %{live_action: action}} = socket
      ) do
    Process.flag(:sensitive, true)

    socket =
      socket
      |> assign(:operating_system, operating_system)
      |> assign_backup_settings()
      |> assign_cargo_settings()
      |> assign_media_settings()

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
          handshaked: false,
          skip_user_creation: Chat.AdminDb.get(:skip_user_creation),
          mode: :user_list,
          monotonic_offset: 0
        )
        |> LocalTimeHook.assign_time(Phoenix.LiveView.get_connect_params(socket)["tz_info"])
        |> allow_any500m_upload(:my_keys_file)
        |> allow_recover_upload()
        |> set_cargo_room()
        |> set_usb_drive_dump_room()
        |> Page.Login.check_stored()
        |> ok()
      end
    else
      socket
      |> ok()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.main {assigns} />
    """
  end

  @impl true
  def handle_params(%{"hash" => hash}, _, %{assigns: %{live_action: :room_message_link}} = socket) do
    socket
    |> assign(:room_message_link_hash, hash)
    |> then(fn socket ->
      if connected?(socket),
        do: Page.LiveRouter.action(socket),
        else: socket
    end)
    |> noreply()
  end

  @impl true
  def handle_params(%{"hash" => hash}, _, %{assigns: %{live_action: :chat_link}} = socket) do
    socket
    |> assign(:chat_link, hash)
    |> then(fn socket ->
      if connected?(socket),
        do: Page.LiveRouter.action(socket),
        else: socket
    end)
    |> noreply()
  end

  def handle_params(_, _, socket), do: socket |> noreply()

  @impl true
  def handle_event("login", %{"login" => %{"name" => name}}, socket) do
    socket
    |> Page.Login.create_user(name)
    |> login_init()
    |> noreply()
  end

  def handle_event("restoreAuth", data, socket) when data == %{} do
    socket
    |> Page.Login.handshaked()
    |> noreply()
  end

  def handle_event("restoreAuth", data, %{assigns: %{live_action: :export}} = socket) do
    socket
    |> Page.Login.load_user(data)
    |> noreply()
  end

  def handle_event("restoreAuth", data, socket) do
    socket
    |> Page.Login.handshaked()
    |> Page.Login.load_user(data)
    |> login_init()
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

  def handle_event("login:recover-key-share", _, socket) do
    socket
    |> Page.Login.close()
    |> assign(:mode, :recover_key_share)
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

  def handle_event("login:recovery-key-close", _, socket) do
    socket
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

  def handle_event("logout-go-share", _, socket) do
    socket
    |> Page.Logout.go_share()
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
    |> Page.Shared.untrack_onliners_presence()
    |> Page.Login.clear()
    |> Page.Logout.wipe()
    |> noreply()
  end

  def handle_event("logout-close", _, socket) do
    socket
    |> Page.Logout.close()
    |> noreply()
  end

  def handle_event("lobby/search", params, socket) do
    socket
    |> Page.Lobby.filter_search_results(params)
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

  def handle_event("put-flash", %{"key" => key, "message" => message}, socket) do
    socket
    |> put_flash(key, message)
    |> noreply()
  end

  def handle_event("cargo:activate", _params, socket) do
    UsbDriveDumpRoom.remove()
    CargoRoom.activate(socket.assigns.room.pub_key)

    %CargoSettings{} = cargo_settings = socket.assigns.cargo_settings
    %Identity{} = me = socket.assigns.me
    %Identity{} = room_identity = socket.assigns.room_identity
    %Room{} = room = socket.assigns.room

    cargo_settings.checkpoints
    |> Enum.each(fn checkpoint ->
      dialog = Dialogs.open(me, checkpoint)

      invites =
        Dialogs.read(dialog, me)
        |> Stream.filter(fn %{type: type} -> type == :room_invite end)
        |> Stream.filter(fn message ->
          identity = Dialogs.extract_invite_room_identity(message)
          identity.public_key == room_identity.public_key
        end)
        |> Enum.to_list()

      if invites == [] do
        room_identity
        |> Map.put(:name, room.name)
        |> Messages.RoomInvite.new()
        |> Dialogs.add_new_message(me, dialog)
        |> RoomInviteIndex.add(dialog, me, room.pub_key)
      end
    end)

    noreply(socket)
  end

  def handle_event("cargo:remove", _params, socket) do
    CargoRoom.remove()
    noreply(socket)
  end

  def handle_event("dump:activate", _params, socket) do
    CargoRoom.remove()

    UsbDriveDumpRoom.activate(
      socket.assigns.room.pub_key,
      socket.assigns.room_identity,
      socket.assigns.monotonic_offset
    )

    noreply(socket)
  end

  def handle_event("dump:remove", _params, socket) do
    UsbDriveDumpRoom.remove()
    noreply(socket)
  end

  def handle_info({:key_shared, _params}, socket) do
    socket
    |> Page.Logout.go_final()
    |> noreply()
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

  def handle_info({:room_request, room_key, user_key}, socket) do
    socket
    |> Page.Lobby.approve_room_request(room_key, user_key)
    |> noreply()
  end

  def handle_info({:room_request_approved, encrypted_room_entity, user_key, room_key}, socket) do
    socket
    |> Page.Lobby.join_approved_room(encrypted_room_entity, user_key, room_key)
    |> noreply()
  end

  def handle_info({:sync_stored_room, key, room_count}, socket) do
    socket
    |> Page.Login.sync_stored_room(key, room_count)
    |> Page.Lobby.show_new_room(%{})
    |> noreply()
  end

  def handle_info(:reset_rooms_to_backup, socket) do
    socket
    |> Page.Login.reset_rooms_to_backup()
    |> noreply()
  end

  def handle_info({:exported_key_ring, keys}, socket) do
    socket
    |> Page.ImportKeyRing.save_key_ring(keys)
    |> Page.Login.store()
    |> Page.ImportKeyRing.close()
    |> login_init()
    |> noreply()
  end

  def handle_info({:db_status, msg}, socket),
    do: socket |> Page.Lobby.set_db_status(msg) |> noreply()

  def handle_info({:free_spaces, msg}, socket),
    do: socket |> Page.AdminPanel.set_free_spaces(msg) |> noreply()

  def handle_info({:room, msg}, socket),
    do: socket |> Page.RoomRouter.info(msg) |> noreply()

  def handle_info({:platform_response, msg}, socket),
    do: socket |> Page.AdminPanelRouter.info(msg) |> noreply()

  def handle_info({:lobby, :refresh_rooms_and_users}, socket),
    do: socket |> Page.Lobby.refresh_rooms_and_users() |> noreply()

  def handle_info({:admin, msg}, socket),
    do: socket |> Page.AdminPanelRouter.info(msg) |> noreply()

  def handle_info({:dialog, msg}, socket), do: socket |> Page.DialogRouter.info(msg) |> noreply()

  def handle_info({ref, :ok}, socket) do
    Process.demonitor(ref, [:flush])

    socket |> noreply()
  end

  def handle_info({ref, {:error, task, _reason}}, socket) do
    Process.demonitor(ref, [:flush])

    socket
    |> process(task)
    |> noreply()
  end

  def handle_info(:update_backup_settings, socket) do
    socket
    |> assign_backup_settings()
    |> noreply()
  end

  def handle_info(:update_cargo_settings, socket) do
    socket
    |> assign_cargo_settings()
    |> noreply()
  end

  def handle_info(:update_media_settings, socket) do
    socket
    |> assign_media_settings()
    |> noreply()
  end

  def handle_info({:create_new_room, %{name: name, type: type}}, socket) do
    socket
    |> Page.Lobby.new_room(name, type)
    |> Page.Room.maybe_enable_cargo()
    |> Page.Room.maybe_enable_usb_drive_dump()
    |> noreply()
  end

  def handle_info({:maybe_activate_cargo_room, true, %Room{} = room, room_identity}, socket) do
    UsbDriveDumpRoom.remove()
    CargoRoom.activate(room.pub_key)

    %CargoSettings{} = cargo_settings = socket.assigns.cargo_settings
    %Identity{} = me = socket.assigns.me

    cargo_settings.checkpoints
    |> Enum.each(fn checkpoint ->
      dialog = Dialogs.find_or_open(me, checkpoint)

      room_identity
      |> Map.put(:name, room.name)
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(me, dialog)
      |> RoomInviteIndex.add(dialog, me, room.pub_key)
    end)

    {:noreply, socket}
  end

  def handle_info({:maybe_activate_cargo_room, _cargo?, _room, _room_identity}, socket),
    do: {:noreply, socket}

  def handle_info({:update_cargo_room, cargo_room}, socket) do
    socket
    |> assign(:cargo_room, cargo_room)
    |> Page.Room.maybe_enable_cargo()
    |> Page.Room.maybe_enable_usb_drive_dump()
    |> noreply()
  end

  def handle_info({:update_usb_drive_dump_progress, dump_room}, socket) do
    socket
    |> assign(:usb_drive_dump_room, dump_room)
    |> noreply()
  end

  def handle_info({:update_usb_drive_dump_room, dump_room}, socket) do
    socket
    |> assign(:usb_drive_dump_room, dump_room)
    |> Page.Room.maybe_enable_cargo()
    |> Page.Room.maybe_enable_usb_drive_dump()
    |> noreply()
  end

  def handle_info({:key_recovered, [me, rooms]}, socket) do
    socket
    |> assign(:step, nil)
    |> assign(:mode, :lobby)
    |> Page.Login.load_user(me, rooms)
    |> Page.Login.store()
    |> login_init()
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

  def loading_screen(assigns) do
    ~H"""
    <img class="vectorGroup bottomVectorGroup" src="/images/bottom_vector_group.svg" />
    <img class="vectorGroup topVectorGroup" src="/images/top_vector_group.svg" />
    <div class="flex flex-col items-center justify-center w-screen h-screen">
      <div class="container unauthenticated z-10">
        <img src="/images/logo.png" />
      </div>
    </div>
    """
  end

  def message_of(%{author_key: _}), do: "room"
  def message_of(_), do: "dialog"

  defp assign_backup_settings(socket) do
    backup_settings = AdminRoom.get_backup_settings()
    assign(socket, :backup_settings, backup_settings)
  end

  defp assign_cargo_settings(socket) do
    cargo_settings = AdminRoom.get_cargo_settings()
    assign(socket, :cargo_settings, cargo_settings)
  end

  defp assign_media_settings(socket) do
    media_settings = AdminRoom.get_media_settings()
    assign(socket, :media_settings, media_settings)
  end

  defp action_confirmation_popup(assigns) do
    ~H"""
    <.modal id={@id} class="">
      <h1 class="text-base font-bold text-grayscale">{@title}</h1>
      <p class="mt-3 text-sm text-black/50">{@description}</p>
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

  defp allow_recover_upload(socket) do
    socket
    |> allow_upload(:recovery_keys,
      auto_upload: true,
      progress: &Page.RecoverKeyShare.handle_progress/3,
      accept: ~w(.social_part),
      max_entries: 100
    )
  end

  defp set_cargo_room(socket) do
    PubSub.subscribe(Chat.PubSub, "chat::cargo_room")

    assign(socket, :cargo_room, CargoRoom.get())
  end

  defp set_usb_drive_dump_room(socket) do
    PubSub.subscribe(Chat.PubSub, "chat::usb_drive_dump_room")

    assign(socket, :usb_drive_dump_room, UsbDriveDumpRoom.get())
  end

  defp login_init(socket) do
    socket
    |> on_login()
  end

  def on_login(socket) do
    socket
    |> Page.Lobby.init()
    |> Page.Dialog.init()
    |> Page.Logout.init()
    |> Page.Shared.track_onliners_presence()
    |> Page.LiveRouter.action()
  end
end
