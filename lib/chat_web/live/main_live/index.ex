defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Chat.Db
  alias Chat.Rooms
  alias ChatWeb.MainLive.Page

  on_mount ChatWeb.Hooks.LocalTimeHook

  @impl true
  def mount(params, _session, %{assigns: %{live_action: action}} = socket) do
    Process.flag(:sensitive, true)

    IO.inspect(2)

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
          shift_key_pressed: false
        )
        |> allow_image_upload(:image)
        |> allow_image_upload(:room_image)
        |> allow_any500m_upload(:backup_file)
        |> allow_any500m_upload(:my_keys_file)
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
    |> noreply()
  end

  def handle_event("restoreAuth", nil, socket), do: socket |> noreply()

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

  def handle_event("switch-lobby-mode:rooms", _, socket) do
    socket
    |> Page.Dialog.close()
    |> Page.Lobby.switch_lobby_mode(:rooms)
    |> Page.Room.init()
    |> noreply()
  end

  def handle_event("switch-lobby-mode:chats", _, socket) do
    socket
    |> Page.Lobby.switch_lobby_mode(:chats)
    |> Page.Dialog.init()
    |> noreply()
  end

  def handle_event("switch-dialog", %{"user-id" => user_id}, socket) do
    socket
    |> Page.Dialog.close()
    |> Page.Dialog.init(user_id)
    |> noreply()
  end

  def handle_event("dialog-message", %{"dialog" => %{"text" => text}}, socket) do
    if String.trim(text) == "" do
      socket
      |> noreply()
    else
      socket
      |> Page.Dialog.send_text(text)
      |> noreply()
    end
  end

  def handle_event("dialog-message", %{"key" => "Shift"} = params, socket) do
    IO.inspect "pressed"
    IO.inspect params
    socket
    |> assign(:shift_key_pressed, true)
    |> noreply()
  end

  def handle_event("dialog-message", %{"key" => "Shift"} = params, socket) do
    IO.inspect "unpressed"
    IO.inspect params
    socket
    |> assign(:shift_key_pressed, false)
    |> noreply()
  end

  def handle_event("dialog-message", %{"key" => "Enter"} = params, %{assigns: %{shift_key_pressed: shift_key_pressed}} = socket) do
    if shift_key_pressed do
      IO.inspect "enter"

    end
    
    socket
    |> noreply()
  end


  def handle_event("dialog-image-change", _, socket), do: socket |> noreply()

  def handle_event("dialog-image-submit", _, socket), do: socket |> noreply()

  def handle_event("close-dialog", _, socket) do
    socket
    |> Page.Dialog.close()
    |> Page.Lobby.init()
    |> noreply()
  end

  def handle_event("create-room", %{"new_room" => %{"name" => name}}, socket) do
    socket
    |> Page.Lobby.new_room(name)
    |> noreply()
  end

  def handle_event("switch-room", %{"room" => hash}, socket) do
    socket
    |> Page.Room.close()
    |> Page.Room.init(hash)
    |> noreply()
  end

  def handle_event("request-room", %{"room" => hash}, socket) do
    socket
    |> Page.Lobby.request_room(hash)
    |> noreply()
  end

  def handle_event("room-message", %{"room" => %{"text" => text}}, socket) do
    if String.trim(text) == "" do
      socket
      |> noreply()
    else
      socket
      |> Page.Room.send_text(text)
      |> noreply()
    end
  end

  def handle_event("room-image-submit", _, socket), do: socket |> noreply()

  def handle_event("export-keys", %{"export_key_ring" => %{"code" => code}}, socket) do
    socket
    |> Page.ExportKeyRing.send_key_ring(code |> String.to_integer())
    |> noreply
  end

  def handle_event("open-feed", _, socket) do
    socket
    |> Page.Lobby.close()
    |> Page.Feed.init()
    |> noreply()
  end

  def handle_event("feed-more", _, socket) do
    socket
    |> Page.Feed.more()
    |> noreply()
  end

  def handle_event("close-feed", _, socket) do
    socket
    |> Page.Feed.close()
    |> Page.Lobby.init()
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
    IO.inspect("open")

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
    ## |> Page.Logout.generate_backup("")
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

  def handle_event(event, params, socket) do
    IO.inspect params, label: :ignore
    socket
    |> noreply()
  end


  @impl true
  def handle_info({:new_dialog_message, glimpse}, socket) do
    socket
    |> Page.Dialog.show_new(glimpse)
    |> noreply()
  end

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

  def handle_info({:new_room_message, glimpse}, socket) do
    socket
    |> Page.Room.show_new(glimpse)
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
    |> noreply()
  end

  def handle_progress(:image, %{done?: true}, socket) do
    socket
    |> Page.Dialog.send_image()
    |> noreply()
  end

  def handle_progress(:room_image, %{done?: true}, socket) do
    socket
    |> Page.Room.send_image()
    |> noreply()
  end

  def handle_progress(:backup_file, %{done?: true}, socket) do
    consume_uploaded_entries(
      socket,
      :backup_file,
      fn %{path: path}, _entry ->
        dir = Temp.mkdir!("rec")
        File.rename!(path, Path.join([dir, "0.cub"]))

        {:ok, other_db} = CubDB.start_link(dir)
        other_db |> Db.copy_data(Db.db())
        Db.db() |> CubDB.file_sync()

        CubDB.stop(other_db)
      end
    )
  end

  def handle_progress(:my_keys_file, %{done?: true}, socket) do
    socket
    |> Page.ImportOwnKeyRing.read_file()
    |> noreply()
  end

  def handle_progress(_file, _entry, socket) do
    socket |> noreply()
  end

  defp message(%{msg: %{type: :text}} = assigns) do
    ~H"""
    <div class={"#{@class} max-w-md min-w-[180px] rounded-lg overflow-hidden shadow-lg"}>
        <.message_header author={@author} />
        <span class="w-full px-2 flex justify-start break-all whitespace-pre-wrap"><%= @msg.content %></span>
        <.message_timestamp msg={@msg} />
      </div>  
    """
  end

  defp message(%{msg: %{type: :image, content: json}} = assigns) do
    [{id, secret}] =
      json
      |> Jason.decode!()
      |> Map.to_list()

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret}")

    ~H"""
      <div class={"#{@class} max-w-md min-w-[180px] rounded-lg overflow-hidden shadow-lg"}>
        <.message_header author={@author} />
        <.message_timestamp msg={@msg} />
        <img 
          title={@msg.timestamp |> DateTime.from_unix!()}
          class="max-w-sm"
          src={@url}
          phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
        />
      </div>  
    """
  end

  defp message_header(assigns) do
    ~H"""
      <div class="py-1 px-2 flex items-center justify-between">
        <div class="flex flex-row">
          <div class="text-sm text-grayscale600">[<%= short_hash(@author.hash) %>]</div>
          <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
        </div>

        <button>
          <svg class="w-4 h-4 flex fill-purple" >
            <use href="/images/icons.svg#menu"></use>
          </svg>
        </button>
      </div>
    """
  end

  defp short_hash(hash), do: hash |> String.split_at(-6) |> elem(1)

  defp message_timestamp(assigns) do
    ~H"""
    <div class="px-2 text-grayscale600 flex justify-end mr-1" style="font-size: 10px;">
      <%= @msg.timestamp |> DateTime.from_unix!() |> Timex.format!("{h12}:{0m} {AM}, {D}.{M}.{YYYY}") %>
    </div>
    """
  end

  defp contact(assigns) do
    ~H"""
    <div class="flex flex-row">
      <div class="text-sm text-grayscale600">[<%= short_hash(@user.hash) %>]</div>
      <div class="ml-1 font-bold text-sm text-purple"><%= @user.name %></div>
    </div>
    """
  end

  defp room_message(%{msg: %{type: :text, author_hash: hash}, my_id: my_id} = assigns) do
    %{name: name} = Chat.User.by_id(hash)

    ~H"""
        <span title={@msg.timestamp |> DateTime.from_unix!()}>
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        <%= @msg.content %>
        </span>
    """
  end

  defp room_message(
         %{msg: %{type: :image, content: json, author_hash: hash}, my_id: my_id} = assigns
       ) do
    [{id, secret}] =
      json
      |> Jason.decode!()
      |> Map.to_list()

    %{name: name} = Chat.User.by_id(hash)

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret}")

    ~H"""
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        <img 
          title={@msg.timestamp |> DateTime.from_unix!()}
          class="preview"
          src={@url}
          phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
        />
    """
  end

  defp allow_image_upload(socket, type) do
    socket
    |> allow_upload(type,
      accept: ~w(.jpg .jpeg .png),
      auto_upload: true,
      max_entries: 1,
      max_size: 60_000_000,
      progress: &handle_progress/3
    )
  end

  defp allow_any500m_upload(socket, type) do
    socket
    |> allow_upload(type,
      auto_upload: true,
      max_file_size: 524_000_000,
      accept: :any,
      max_entries: 1,
      progress: &handle_progress/3
    )
  end
end
