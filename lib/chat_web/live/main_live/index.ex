defmodule ChatWeb.MainLive.Index do
  @moduledoc "Main Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias Chat.Db
  alias Chat.Files
  alias Chat.Memo
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

  def handle_event("login:import-own-keyring-close", _, socket) do
    socket
    |> Page.ImportKeyRing.close()
    |> assign(:need_login, true)
    |> noreply()
  end

  def handle_event("open-dialog", %{"user-id" => user_id}, socket) do
    socket
    |> Page.Lobby.close()
    |> Page.Dialog.init(user_id)
    |> noreply()
  end

  def handle_event("dialog-message", %{"dialog" => %{"text" => text}}, socket) do
    socket
    |> Page.Dialog.send_text(text)
    |> noreply()
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

  def handle_event("dialog/delete-message", %{"id" => id, "timestamp" => time}, socket) do
    socket
    |> Page.Dialog.delete_message({time |> String.to_integer(), id})
    |> noreply()
  end

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

  def handle_event("open-room", %{"room" => hash}, socket) do
    socket
    |> Page.Lobby.close()
    |> Page.Room.init(hash)
    |> noreply()
  end

  def handle_event("request-room", %{"room" => hash}, socket) do
    socket
    |> Page.Lobby.request_room(hash)
    |> noreply()
  end

  def handle_event("room-message", %{"room" => %{"text" => text}}, socket) do
    socket
    |> Page.Room.send_text(text)
    |> noreply()
  end

  def handle_event("room/cancel-edit", _, socket) do
    socket
    |> Page.Room.cancel_edit()
    |> noreply()
  end

  def handle_event("room/edited-message", %{"room_edit" => %{"text" => text}}, socket) do
    socket
    |> Page.Room.update_edited_message(text)
    |> noreply()
  end

  def handle_event("room/edit-message", %{"id" => id, "timestamp" => time}, socket) do
    socket
    |> Page.Room.edit_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event("room/delete-message", %{"id" => id, "timestamp" => time}, socket) do
    socket
    |> Page.Room.delete_message({time |> String.to_integer(), id})
    |> noreply()
  end

  def handle_event("room-image-submit", _, socket), do: socket |> noreply()
  def handle_event("room-file-submit", _, socket), do: socket |> noreply()

  def handle_event("close-room", _, socket) do
    socket
    |> Page.Room.close()
    |> Page.Lobby.init()
    |> noreply()
  end

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
    |> assign(:mode, :user_list)
    |> noreply()
  end

  def handle_event("logout-open", _, socket) do
    socket
    |> Page.Lobby.close()
    |> Page.Logout.init()
    |> noreply()
  end

  def handle_event("logout-go-middle", _, socket) do
    socket
    |> Page.Logout.go_middle()
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
    |> Page.Lobby.init()
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
    |> Page.Dialog.update_message(msg_id, &message/1)
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

  def handle_info({:room, {:new_message, glimpse}}, socket) do
    socket
    |> Page.Room.show_new(glimpse)
    |> noreply()
  end

  def handle_info({:room, {:updated_message, msg_id}}, socket) do
    socket
    |> Page.Room.update_message(msg_id, &room_message/1)
    |> noreply()
  end

  def handle_info({:room, {:deleted_message, msg_id}}, socket) do
    socket
    |> push_event("chat:toggle", %{to: "#room-message-#{msg_id}", class: "hidden"})
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

  def message(%{msg: %{type: :text}} = assigns) do
    ~H"""
        <span title={@msg.timestamp |> DateTime.from_unix!()}><%= @msg.content %></span>
    """
  end

  def message(%{msg: %{type: :memo, content: json}} = assigns) do
    memo =
      json
      |> StorageId.from_json()
      |> Memo.get()

    assigns = assigns |> Map.put(:memo, memo)

    ~H"""
        <span title={@msg.timestamp |> DateTime.from_unix!()}><%= @memo %></span>
    """
  end

  def message(%{msg: %{type: :image, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret |> Base.url_encode64()}")

    ~H"""
        <img 
          title={@msg.timestamp |> DateTime.from_unix!()}
          class="preview"
          src={@url}
          phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
        />
    """
  end

  def message(%{msg: %{type: :file, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()
    [_, _, name, size] = Files.get(id, secret)

    assigns =
      assigns
      |> Map.put(:url, "/get/file/#{id}?a=#{secret |> Base.url_encode64()}")
      |> Map.put(:name, name)
      |> Map.put(:size, size)

    ~H"""
        <div title={@msg.timestamp |> DateTime.from_unix!()}
          style="margin: 1em"
        >
          file: 
          <a href={@url}><%= @name %></a>
          (<%= @size %>)
        </div>
    """
  end

  def room_message(%{msg: %{type: :text, author_hash: hash}, my_id: my_id} = assigns) do
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

  def room_message(
        %{msg: %{type: :memo, author_hash: hash, content: json}, my_id: my_id} = assigns
      ) do
    %{name: name} = Chat.User.by_id(hash)

    memo =
      json
      |> StorageId.from_json()
      |> Memo.get()

    ~H"""
        <span title={@msg.timestamp |> DateTime.from_unix!()} style="word-wrap: break-word;">
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        <%= memo %>
        </span>
    """
  end

  def room_message(
        %{msg: %{type: :image, content: json, author_hash: hash}, my_id: my_id} = assigns
      ) do
    {id, secret} = json |> StorageId.from_json()
    url = "/get/image/#{id}?a=#{secret |> Base.url_encode64()}"
    %{name: name} = Chat.User.by_id(hash)

    ~H"""
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        <img 
          title={@msg.timestamp |> DateTime.from_unix!()}
          class="preview"
          src={url}
          phx-click={JS.dispatch("chat:toggle", detail: %{class: "preview"})}
        />
    """
  end

  def room_message(
        %{msg: %{type: :file, content: json, author_hash: hash}, my_id: my_id} = assigns
      ) do
    {id, secret} = json |> StorageId.from_json()
    [_, _, file_name, size] = Files.get(id, secret)
    url = "/get/file/#{id}?a=#{secret |> Base.url_encode64()}"

    %{name: name} = Chat.User.by_id(hash)

    ~H"""
      <span title={@msg.timestamp |> DateTime.from_unix!()} >
        <%= unless hash == my_id do %>
          <i><%= name %></i>:
        <% end %>
        file: 
        <a href={url}><%= file_name %></a>
        (<%= size %>)
      </span>
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
