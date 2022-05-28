defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Chat.Db
  alias Chat.Rooms
  alias Chat.Files
  alias Chat.Memo
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Page

  on_mount ChatWeb.Hooks.LocalTimeHook

  @impl true
  def mount(params, _session, %{assigns: %{live_action: action}} = socket) do
    Process.flag(:sensitive, true)

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
          mode: :user_list
        )
        |> allow_image_upload(:image)
        |> allow_image_upload(:room_image)
        |> allow_any500m_upload(:backup_file)
        |> allow_any500m_upload(:my_keys_file)
        |> allow_any500m_upload(:dialog_file)
        |> allow_any500m_upload(:room_file)
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

  def handle_event("switch-dialog", %{"user-id" => user_id}, socket) do
    socket
    |> Page.Dialog.close()
    |> Page.Dialog.init(user_id)
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

  def handle_event("dialog-image-change", _, socket), do: socket |> noreply()
  def handle_event("dialog-image-submit", _, socket), do: socket |> noreply()
  def handle_event("dialog-file-change", _, socket), do: socket |> noreply()
  def handle_event("dialog-file-submit", _, socket), do: socket |> noreply()

  def handle_event("dialog/cancel-edit", _, socket) do
    socket
    |> Page.Dialog.cancel_edit()
    |> noreply()
  end

  def handle_event("dialog/edited-message", %{"dialog_edit" => %{"text" => text}}, socket) do
    socket
    |> Page.Dialog.update_edited_message(text)
    |> noreply()
  end

  def handle_event("dialog/edit-message", %{"id" => id, "timestamp" => time}, socket) do
    socket
    |> Page.Dialog.edit_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event(
        "delete-message",
        %{"id" => id, "timestamp" => time, "type" => "dialog"},
        socket
      ) do
    socket
    |> Page.Dialog.delete_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event("dialog/download-message", %{"id" => id, "timestamp" => time}, socket) do
    socket
    |> Page.Dialog.download_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event("close-dialog", _, socket) do
    socket
    |> Page.Dialog.close()
    |> noreply()
  end

  def handle_event("close-room", _, socket) do
    socket
    |> Page.Room.close()
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

  def handle_event("room/download-message", %{"id" => id, "timestamp" => time}, socket) do
    socket
    |> Page.Room.download_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event("delete-message", %{"id" => id, "timestamp" => time, "type" => "room"}, socket) do
    socket
    |> Page.Room.delete_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event("room-image-submit", _, socket), do: socket |> noreply()
  def handle_event("room-file-submit", _, socket), do: socket |> noreply()

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

  def handle_event("room/" <> event, params, socket) do
    socket
    |> Page.RoomRouter.event({event, params})
    |> noreply()
  end

  @impl true
  def handle_info({:new_dialog_message, glimpse}, socket) do
    socket
    |> Page.Dialog.show_new(glimpse)
    |> noreply()
  end

  def handle_info({:updated_dialog_message, msg_id}, socket) do
    socket
    |> Page.Dialog.update_message(msg_id, &message_text/1)
    |> noreply()
  end

  def handle_info({:deleted_dialog_message, msg_id}, socket) do
    socket
    |> push_event("chat:toggle", %{to: "#dialog-message-#{msg_id}", class: "hidden"})
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

  def handle_info({:room, msg}, socket), do: socket |> Page.RoomRouter.info(msg)

  def handle_progress(:image, %{done?: true}, socket) do
    socket
    |> Page.Dialog.send_image()
    |> noreply()
  end

  def handle_progress(:dialog_file, %{done?: true}, socket) do
    socket
    |> Page.Dialog.send_file()
    |> noreply()
  end

  def handle_progress(:room_image, %{done?: true}, socket) do
    socket
    |> Page.Room.send_image()
    |> noreply()
  end

  def handle_progress(:room_file, %{done?: true}, socket) do
    socket
    |> Page.Room.send_file()
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

  def message(%{msg: %{type: type}} = assigns) when type in [:text, :memo] do
    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <span class="x-content"><.message_text msg={@msg} /></span>
      <.message_timestamp msg={@msg} />
    </div>  
    """
  end

  def message(%{msg: %{type: :image, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret |> Base.url_encode64()}")

    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <.message_timestamp msg={@msg} />
      <.message_image url={@url} /> 
    </div>  
    """
  end

  def message(%{msg: %{type: :file}} = assigns) do
    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <.message_file msg={@msg} />
      <.message_timestamp msg={@msg} />
    </div>  
    """
  end

  def message_text(%{msg: %{type: :text}} = assigns) do
    ~H"""
    <span class="w-full px-2 flex justify-start break-all whitespace-pre-wrap"><%= @msg.content %></span>
    """
  end

  def message_text(%{msg: %{type: :memo, content: json}} = assigns) do
    memo =
      json
      |> StorageId.from_json()
      |> Memo.get()

    assigns = assigns |> Map.put(:memo, memo)

    ~H"""
    <span class="w-full px-2 flex justify-start break-all whitespace-pre-wrap"><%= @memo %></span>
    """
  end

  defp message_file(%{msg: %{type: :file, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()
    [_, _, name, size] = Files.get(id, secret)

    assigns =
      assigns
      |> Map.put(:url, "/get/file/#{id}?a=#{secret |> Base.url_encode64()}")
      |> Map.put(:name, name)
      |> Map.put(:size, size)

    ~H"""
    <div class="flex items-center justify-between">
      <.icon id="document" class="w-14 h-14 flex fill-black/50"/>
      <div class="w-36 flex flex-col pr-3">
        <span class="truncate text-xs" href={@url}><%= @name %></span>
        <span class="text-xs text-black/50 whitespace-pre-line"><%= @size %></span>
      </div>
    </div>  
    """
  end

  defp message_header(assigns) do
    ~H"""
    <div id={"message-header-#{@msg.id}"} class="py-1 px-2 flex items-center justify-between relative">
      <div class="flex flex-row">
        <div class="text-sm text-grayscale600">[<%= short_hash(@author.hash) %>]</div>
        <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
      </div>
      <button phx-click={open_dropdown("messageActionsDropdown-#{@msg.id}") 
                         |> JS.dispatch("chat:set-dropdown-position", to: "#messageActionsDropdown-#{@msg.id}", detail: %{relativeElementId: "message-#{@msg.id}"})}
      >
        <.icon id="menu" class="w-4 h-4 flex fill-purple"/>
      </button>
      <.dropdown id={"messageActionsDropdown-#{@msg.id}"} >
        <%= if @is_mine do %>
          <%= if @msg.type in [:text, :memo] do %>
            <a class="dropdownItem"
              phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}") |> JS.push("#{message_of(@msg)}/edit-message")} 
              phx-value-id={@msg.id} 
              phx-value-timestamp={@msg.timestamp}
            > 
              <.icon id="edit" class="w-4 h-4 flex fill-black"/>
              <span>Edit</span>
            </a>
          <% end %> 
          <a class="dropdownItem"
            phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}") 
                       |> show_modal("delete-message-popup")
                       |> JS.set_attribute({"phx-value-id", @msg.id}, to: "#delete-message-popup .deleteMessageButton") 
                       |> JS.set_attribute({"phx-value-timestamp", @msg.timestamp}, to: "#delete-message-popup .deleteMessageButton")
                       |> JS.set_attribute({"phx-value-type", message_of(@msg)}, to: "#delete-message-popup .deleteMessageButton")
                      }
            phx-value-id={@msg.id}
            phx-value-timestamp={@msg.timestamp}
            phx-value-type="dialog-message"
          > 
            <.icon id="delete" class="w-4 h-4 flex fill-black"/>
            <span>Delete</span>
          </a>
        <% end %> 
        <a phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}")} class="dropdownItem"> 
          <.icon id="share" class="w-4 h-4 flex fill-black"/>
          <span>Share</span>
        </a>
        <%= if @msg.type in [:file, :image] do %>
          <a 
            class="dropdownItem"
            phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}") |> JS.push("#{message_of(@msg)}/download-message")}  
            phx-value-id={@msg.id} 
            phx-value-timestamp={@msg.timestamp}
          > 
            <.icon id="download" class="w-4 h-4 flex fill-black"/>
            <span>Download</span>
          </a>
        <% end %> 
      </.dropdown>
    </div>
    """
  end

  defp message_image(assigns) do
    ~H"""
    <img class=" object-cover overflow-hidden" src={@url} phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
    />
    """
  end

  defp message_timestamp(assigns) do
    ~H"""
    <div class="px-2 text-grayscale600 flex justify-end mr-1" style="font-size: 10px;">
      <%= @msg.timestamp |> DateTime.from_unix!() |> Timex.format!("{h12}:{0m} {AM}, {D}.{M}.{YYYY}") %>
    </div>
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

  def short_hash(hash), do: hash |> String.split_at(-6) |> elem(1)

  defp allow_image_upload(socket, type) do
    socket
    |> allow_upload(type,
      accept: ~w(.jpg .jpeg .png),
      auto_upload: true,
      max_entries: 1,
      max_file_size: 60_000_000,
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
