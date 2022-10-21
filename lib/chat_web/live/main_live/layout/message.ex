defmodule ChatWeb.MainLive.Layout.Message do
  @moduledoc "Message layout"
  use Phoenix.Component

  import ChatWeb.LiveHelpers
  import ChatWeb.MainLive.Index

  alias Chat.Files
  alias Chat.Identity
  alias Chat.Memo
  alias Chat.RoomInvites
  alias Chat.Utils.StorageId
  # alias ChatWeb.Router.Helpers
  alias Phoenix.LiveView.JS

  def render(%{msg: %{type: type}} = assigns) do
    case type do
      :file -> render_file(assigns)
      :video -> render_video(assigns)
      :image -> render_image(assigns)
      :request -> render_room_request(assigns)
      :room_invite -> render_room_invite(assigns)
      _ -> render_text(assigns)
    end
  end

  def render_text(%{msg: %{type: type}} = assigns) when type in [:text, :memo] do
    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <span class="x-content"><.message_text msg={@msg} /></span>
      <.message_timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  def render_room_invite(%{msg: %{type: :room_invite, content: json}} = assigns) do
    identity =
      json
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    assigns =
      assigns
      |> Map.put(:room_name, identity.name)
      |> Map.put(:room_hash, Chat.Utils.hash(identity))

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
           phx-click="dialog/message/accept-room-invite"
           phx-value-id={@msg.id}
           phx-value-index={@msg.index}
          >Accept</button>
          <button class="w-[49%] h-12 border-0 rounded-lg bg-grayscale text-white"
           phx-click="dialog/message/accept-room-invite-and-open-room"
           phx-value-id={@msg.id}
           phx-value-index={@msg.index}
          >Accept and Open</button>
        </div>
      <% end %>
      <.message_timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  def render_room_request(assigns) do
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
      <.message_timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  def render_image(%{msg: %{type: :image, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()

    assigns =
      assigns
      |> Map.put(:url, "/get/image/#{id}?a=#{secret |> Base.url_encode64()}")

    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <.message_timestamp msg={@msg} timezone={@timezone} />
      <.message_image url={@url} mode={message_of(@msg)} msg_id={@msg.id} msg_index={@msg.index}/>
    </div>
    """
  end

  def render_video(%{msg: %{type: :video, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()

    assigns =
      assigns
      |> Map.put(:url, "/get/file/#{id}?a=#{secret |> Base.url_encode64()}")

    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <.message_timestamp msg={@msg} timezone={@timezone} />
      <.message_video url={@url} />
    </div>
    """
  end

  def render_file(%{msg: %{type: :file}} = assigns) do
    ~H"""
    <div id={"message-#{@msg.id}"} class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}>
      <.message_header msg={@msg} author={@author} is_mine={@is_mine} />
      <.message_file msg={@msg} />
      <.message_timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  def message_text(%{msg: %{type: :text}} = assigns) do
    ~H"""
    <div class="px-4 w-full">
      <span class="flex-initial break-words">
        <%= @msg.content %>
      </span>
    </div>
    """
  end

  def message_text(%{msg: %{type: :memo, content: json}} = assigns) do
    memo =
      json
      |> StorageId.from_json()
      |> Memo.get()

    assigns = assigns |> Map.put(:memo, memo)

    ~H"""
    <div class="px-4 w-full ">
      <span class="flex-initial break-words">
        <%= @memo %>
      </span>
    </div>
    """
  end

  defp message_file(%{msg: %{type: :file, content: json}} = assigns) do
    {id, secret} = json |> StorageId.from_json()
    [_, _, _, _, name, size] = Files.get(id, secret)

    assigns =
      assigns
      |> Map.put(:url, "/get/file/#{id}?a=#{secret |> Base.url_encode64()}")
      |> Map.put(:name, name)
      |> Map.put(:size, size)

    ~H"""
    <div class="flex items-center justify-between">
      <.icon id="document" class="w-14 h-14 flex fill-black/50"/>
      <div class="w-36 flex flex-col pr-3">
        <span class="truncate text-xs x-file" href={@url}><%= @name %></span>
        <span class="text-xs text-black/50 whitespace-pre-line"><%= @size %></span>
      </div>
    </div>
    """
  rescue
    _ ->
      ~H"""
      <div class="flex items-center justify-between">
        Error getting file
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
      <button type="button" class="messageActionsDropdownButton hiddenUnderSelection t-message-dropdown" phx-click={open_dropdown("messageActionsDropdown-#{@msg.id}")
                         |> JS.dispatch("chat:set-dropdown-position", to: "#messageActionsDropdown-#{@msg.id}", detail: %{relativeElementId: "message-#{@msg.id}"})}
      >
        <.icon id="menu" class="w-4 h-4 flex fill-purple"/>
      </button>
      <.dropdown class="messageActionsDropdown " id={"messageActionsDropdown-#{@msg.id}"} >
        <%= if @is_mine do %>
          <%= if @msg.type in [:text, :memo] do %>
            <a class="dropdownItem t-edit-message"
              phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}") |> JS.push("#{message_of(@msg)}/message/edit")}
              phx-value-id={@msg.id}
              phx-value-index={@msg.index}
            >
              <.icon id="edit" class="w-4 h-4 flex fill-black"/>
              <span>Edit</span>
            </a>
          <% end %>
          <a class="dropdownItem t-delete-message"
            phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}")
                       |> show_modal("delete-message-popup")
                       |> JS.set_attribute({"phx-click", hide_modal("delete-message-popup") |> JS.push(message_of(@msg) <> "/delete-messages") |> stringify_commands()}, to: "#delete-message-popup .deleteMessageButton")
                       |> JS.set_attribute({"phx-value-messages", [%{id: @msg.id, index: "#{@msg.index}"}] |> Jason.encode!}, to: "#delete-message-popup .deleteMessageButton")
                      }
            phx-value-id={@msg.id}
            phx-value-index={@msg.index}
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
        <a class="dropdownItem t-select-message"
           phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}")
                     |> JS.push("#{message_of(@msg)}/toggle-messages-select", value: %{action: :on, id: @msg.id, chatType: message_of(@msg)})
                     |> JS.dispatch("chat:select-message", to: "#message-block-#{@msg.id}", detail: %{chatType: message_of(@msg)})
                     }>
          <.icon id="select" class="w-4 h-4 flex fill-black"/>
          <span>Select</span>
        </a>
        <%= if @msg.type in [:file, :image, :video] do %>
          <a
            class="dropdownItem"
            phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}")
                      |> JS.push("#{message_of(@msg)}/message/download")
                      }
            phx-value-id={@msg.id}
            phx-value-index={@msg.index}
          >
            <.icon id="download" class="w-4 h-4 flex fill-black"/>
            <span>Download</span>
          </a>
        <% end %>
      </.dropdown>
    </div>
    """
  end

  defp message_video(assigns) do
    ~H"""
    <video src={@url} controls />
    """
  end

  defp message_image(assigns) do
    # {JS.dispatch("chat:toggle", detail: %{class: "preview"})
    #  |> JS.add_class("hidden", to: "#dialogInput")
    #  |> JS.add_class("md:hidden", to: "#chatRoomBar")
    #  |> JS.add_class("hidden", to: "#chatContent")
    #  |> JS.remove_class("hidden", to: "#imageGallery")
    #  |> JS.remove_class("overflow-scroll", to: "#chatContent")}
    ~H"""
      <img
        class="object-cover overflow-hidden"
        src={@url}
        phx-click={JS.push("#{@mode}/message/open-image-gallery") |> JS.add_class("hidden", to: "#chatContent")}
        phx-value-id={@msg_id}
        phx-value-index={@msg_index}
      />
    """
  end

  defp message_timestamp(%{msg: %{timestamp: timestamp}, timezone: timezone} = assigns) do
    time =
      timestamp
      |> DateTime.from_unix!()
      |> DateTime.shift_zone!(timezone)
      |> Timex.format!("{h12}:{0m} {AM}, {D}.{M}.{YYYY}")

    assigns = Map.put(assigns, :time, time)

    ~H"""
    <div class="px-2 text-grayscale600 flex justify-end mr-1" style="font-size: 10px;">
      <%= @time%>
    </div>
    """
  end
end
