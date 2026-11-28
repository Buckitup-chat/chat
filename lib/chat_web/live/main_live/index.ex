defmodule ChatWeb.MainLive.Index do
  @moduledoc """
  Main Liveview. Mounts the session and dispatches events and messages to page routers:
  `Page.LoginRouter`, `Page.LogoutRouter`, `Page.LobbyRouter`, `Page.SyncRoomRouter`,
  `Page.DialogRouter`, `Page.RoomRouter`, `Page.AdminPanelRouter` and `Page.LiveRouter`.

  Markup lives in the embedded `*.html.heex` templates next to this module.
  """
  use ChatWeb, :live_view

  alias Chat.AdminRoom
  alias Chat.Rooms.Room
  alias ChatWeb.Hooks.{LiveModalHook, LocalTimeHook, UploaderHook}

  alias ChatWeb.MainLive.Admin.{
    BackupSettingsForm,
    CargoCameraSensorsForm,
    CargoCheckpointsForm,
    CargoUserData,
    CargoWeightSensorForm,
    FirmwareUpgradeForm,
    GithubFirmwareUpgradeForm,
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

  on_mount LiveModalHook
  on_mount LocalTimeHook
  on_mount UploaderHook

  embed_templates "*"

  @login_events ~W(login restoreAuth export-keys)
  @lobby_events ~W(switch-lobby-mode lobby/search chat:load-more feed-more open-data-restore backup-file-submit close-data-restore)
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

    cond do
      not connected?(socket) -> socket
      action == :export -> socket |> init_export(params["id"])
      true -> socket |> init_session()
    end
    |> ok()
  end

  defp init_export(socket, id) do
    socket
    |> assign(need_login: false, monotonic_offset: 0)
    |> Page.ExportKeyRing.init(id)
    |> Page.Login.check_stored()
  end

  defp init_session(socket) do
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
    |> Page.SyncRoomRouter.init()
    |> Page.Login.check_stored()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.main {assigns} />
    """
  end

  @impl true
  def handle_params(params, _, socket),
    do: socket |> Page.LiveRouter.params(params) |> noreply()

  @impl true
  def handle_event(event, params, socket) when event in @login_events,
    do: socket |> Page.LoginRouter.event({event, params}) |> noreply()

  def handle_event("login:" <> _ = event, params, socket),
    do: socket |> Page.LoginRouter.event({event, params}) |> noreply()

  def handle_event("logout" <> _ = event, params, socket),
    do: socket |> Page.LogoutRouter.event({event, params}) |> noreply()

  def handle_event(event, params, socket) when event in @lobby_events,
    do: socket |> Page.LobbyRouter.event({event, params}) |> noreply()

  def handle_event("cargo:" <> _ = event, params, socket),
    do: socket |> Page.SyncRoomRouter.event({event, params}) |> noreply()

  def handle_event("dump:" <> _ = event, params, socket),
    do: socket |> Page.SyncRoomRouter.event({event, params}) |> noreply()

  def handle_event("dialog/" <> event, params, socket),
    do: socket |> Page.DialogRouter.event({event, params}) |> noreply()

  def handle_event("room/" <> event, params, socket),
    do: socket |> Page.RoomRouter.event({event, params}) |> noreply()

  def handle_event("admin/" <> event, params, socket),
    do: socket |> Page.AdminPanelRouter.event({event, params}) |> noreply()

  def handle_event("client-timestamp", %{"timestamp" => timestamp}, socket),
    do: socket |> assign(:monotonic_offset, Chat.Time.monotonic_offset(timestamp)) |> noreply()

  def handle_event("put-flash", %{"key" => key, "message" => message}, socket),
    do: socket |> put_flash(key, message) |> noreply()

  @impl true
  def handle_info({:key_shared, _} = message, socket),
    do: socket |> Page.LogoutRouter.info(message) |> noreply()

  def handle_info({:exported_key_ring, _} = message, socket),
    do: socket |> Page.LoginRouter.info(message) |> noreply()

  def handle_info({:key_recovered, _} = message, socket),
    do: socket |> Page.LoginRouter.info(message) |> noreply()

  def handle_info({:sync_stored_room, _, _} = message, socket),
    do: socket |> Page.LoginRouter.info(message) |> noreply()

  def handle_info(:reset_rooms_to_backup = message, socket),
    do: socket |> Page.LoginRouter.info(message) |> noreply()

  def handle_info({:new_user, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:new_room, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:room_request, _, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:room_request_approved, _, _, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:create_new_room, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:lobby, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:db_status, _} = message, socket),
    do: socket |> Page.LobbyRouter.info(message) |> noreply()

  def handle_info({:maybe_activate_cargo_room, _, _, _} = message, socket),
    do: socket |> Page.SyncRoomRouter.info(message) |> noreply()

  def handle_info({:update_cargo_room, _} = message, socket),
    do: socket |> Page.SyncRoomRouter.info(message) |> noreply()

  def handle_info({:update_usb_drive_dump_progress, _} = message, socket),
    do: socket |> Page.SyncRoomRouter.info(message) |> noreply()

  def handle_info({:update_usb_drive_dump_room, _} = message, socket),
    do: socket |> Page.SyncRoomRouter.info(message) |> noreply()

  def handle_info({:free_spaces, msg}, socket),
    do: socket |> Page.AdminPanel.set_free_spaces(msg) |> noreply()

  def handle_info({:room, msg}, socket),
    do: socket |> Page.RoomRouter.info(msg) |> noreply()

  def handle_info({:platform_response, msg}, socket),
    do: socket |> Page.AdminPanelRouter.info(msg) |> noreply()

  def handle_info({:admin, msg}, socket),
    do: socket |> Page.AdminPanelRouter.info(msg) |> noreply()

  def handle_info({:dialog, msg}, socket), do: socket |> Page.DialogRouter.info(msg) |> noreply()

  def handle_info({ref, :ok}, socket), do: socket |> forget_task(ref) |> noreply()

  def handle_info({ref, {:error, task, _reason}}, socket),
    do: socket |> forget_task(ref) |> process(task) |> noreply()

  def handle_info(:update_backup_settings, socket),
    do: socket |> assign_backup_settings() |> noreply()

  def handle_info(:update_cargo_settings, socket),
    do: socket |> assign_cargo_settings() |> noreply()

  def handle_info(:update_media_settings, socket),
    do: socket |> assign_media_settings() |> noreply()

  def handle_info({:push_patch, url}, socket), do: socket |> push_patch(to: url) |> noreply()

  def handle_progress(:my_keys_file, %{done?: true}, socket),
    do: socket |> Page.ImportOwnKeyRing.read_file() |> noreply()

  def handle_progress(_file, _entry, socket), do: socket |> noreply()

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

  defp forget_task(socket, ref) do
    Process.demonitor(ref, [:flush])
    socket
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
end
