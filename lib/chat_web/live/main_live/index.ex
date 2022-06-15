defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Chat.Db
  alias Chat.Files
  alias Chat.Identity
  alias Chat.Memo
  alias Chat.RoomInvites
  alias Chat.Rooms
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
        |> allow_any500m_upload(:dialog_file, max_entries: 50)
        |> allow_any500m_upload(:room_file, max_entries: 50)
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

  def handle_info({:room, msg}, socket),
    do: socket |> Page.RoomRouter.info(msg) |> noreply()

  def handle_info({:platform_response, msg}, socket),
    do: socket |> Page.AdminPanelRouter.info(msg) |> noreply()

  def handle_info({:dialog, msg}, socket), do: socket |> Page.DialogRouter.info(msg) |> noreply()

  def handle_progress(:image, %{done?: true} = entry, socket) do
    socket
    |> Page.Dialog.send_image(entry)
    |> noreply()
  end

  def handle_progress(:dialog_file, %{done?: true} = entry, socket) do
    socket
    |> Page.Dialog.send_file(entry)
    |> noreply()
  end

  def handle_progress(:room_image, %{done?: true} = entry, socket) do
    socket
    |> Page.Room.send_image(entry)
    |> noreply()
  end

  def handle_progress(:room_file, %{done?: true} = entry, socket) do
    socket
    |> Page.Room.send_file(entry)
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

  defp flash_notification(assigns) do
    ~H"""
    <div id={@id} class={"flex items-center justify-between w-screen sm:w-96 min-h-fit z-30 bg-green-400 rounded-lg text-teal-900 px-4 py-3 shadow-md centered"} role="alert" style="display: none;">
      <div class="flex items-center">
        <.icon id="checked" class="w-5 h-5 fill-white"/>
        <p class="ml-2 text-white">Invitation Sent!</p>
      </div>
      <div phx-click={JS.hide(to: "#" <> @id)}>
        <.icon id="close" class="w-5 h-5 fill-white cursor-pointer" />
      </div>
    </div>
    """
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

  def message(%{msg: %{type: :room_invite, content: json}} = assigns) do
    {hash, _} = info = json |> StorageId.from_json()

    name =
      info
      |> RoomInvites.get()
      |> Identity.from_strings()
      |> Map.get(:name)

    assigns =
      assigns
      |> Map.put(:room_name, name)
      |> Map.put(:room_hash, hash)

    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <div class="py-1 px-2">
        <div class="inline-flex">
          <div class=" font-bold text-sm text-purple">[<%= short_hash(@author.hash) %>]</div>
          <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
        </div>
        <p class="inline-flex">wants you to join the room </p>
        <div class="inline-flex">        
          <div class="font-bold text-sm text-purple">[<%= short_hash(@room_hash) %>]</div>
          <h1 class="ml-1 font-bold text-sm text-purple" ><%= @room_name %></h1>
        </div>
      </div>


       
      <%= unless @is_mine do %>
        <div class="px-2 my-1 flex items-center justify-between">
          <button class="w-[49%] h-12 border-0 rounded-lg bg-grayscale text-white"
           phx-click="dialog/accept-room-invite"
           phx-value-id={@msg.id}
           phx-value-time={@msg.timestamp}
          >Accept</button>
          <button class="w-[49%] h-12 border-0 rounded-lg bg-grayscale text-white"
           phx-click="dialog/accept-room-invite-and-open-room"
           phx-value-id={@msg.id}
           phx-value-time={@msg.timestamp}
          >Accept and Open</button>
        </div>
      <% end %>
      <.message_timestamp msg={@msg} />
    </div>  
    """
  end

  def message(%{msg: %{type: :request}} = assigns) do
    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <div class="py-1 px-2">
        <div class="inline-flex">
          <div class=" font-bold text-sm text-purple">[<%= short_hash(@author.hash) %>]</div>
          <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
        </div>
        <p class="inline-flex">requested access to room </p>
        <div class="inline-flex">        
          <div class="font-bold text-sm text-purple">[<%= short_hash(@room.admin_hash) %>]</div>
          <h1 class="ml-1 font-bold text-sm text-purple" ><%= @room.name %></h1>
        </div>
      </div>
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
    [name, size] = Files.get_meta(id, secret)

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
      <button type="button" class="messageActionsDropdownButton hiddenUnderSelection" phx-click={open_dropdown("messageActionsDropdown-#{@msg.id}") 
                         |> JS.dispatch("chat:set-dropdown-position", to: "#messageActionsDropdown-#{@msg.id}", detail: %{relativeElementId: "message-#{@msg.id}"})}
      >
        <.icon id="menu" class="w-4 h-4 flex fill-purple"/>
      </button>
      <.dropdown class="messageActionsDropdown " id={"messageActionsDropdown-#{@msg.id}"} >
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
                       |> JS.set_attribute({"phx-click", hide_modal("delete-message-popup") |> JS.push(message_of(@msg) <> "/delete-messages") |> stringify_commands()}, to: "#delete-message-popup .deleteMessageButton") 
                       |> JS.set_attribute({"phx-value-messages", [%{id: @msg.id, timestamp: "#{@msg.timestamp}"}] |> Jason.encode!}, to: "#delete-message-popup .deleteMessageButton") 
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
        <a class="dropdownItem"
           phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}")
                     |> JS.push("#{message_of(@msg)}/toggle-messages-select", value: %{action: :on, id: @msg.id, chatType: message_of(@msg)})
                     |> JS.dispatch("chat:select-message", to: "#message-block-#{@msg.id}", detail: %{chatType: message_of(@msg)})
                     }> 
          <.icon id="select" class="w-4 h-4 flex fill-black"/>
          <span>Select</span>
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
      max_entries: 50,
      max_file_size: 60_000_000,
      progress: &handle_progress/3
    )
  end

  defp allow_any500m_upload(socket, type, opts \\ []) do
    socket
    |> allow_upload(type,
      auto_upload: true,
      max_file_size: 524_000_000,
      accept: :any,
      max_entries: Keyword.get(opts, :max_entries, 1),
      progress: &handle_progress/3
    )
  end
end
