defmodule ChatWeb.MainLive.Layout.Message do
  @moduledoc """
  Message layout
  Used both for rendering regular and exported messages.

  Message is passed under :msg attribute as either
  either %Chat.Dialogs.PrivateMessage{} (dialog message)
  or Chat.Rooms.PlainMessage{} (room message).
  """
  require Logger

  use ChatWeb, :component

  alias Chat.Card
  alias Chat.Content.Files
  alias Chat.Content.Memo
  alias Chat.Content.RoomInvites
  alias Chat.Identity
  alias Chat.Messages.ExportHelper
  alias Chat.Rooms.Room
  alias Chat.User
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Layout
  alias ChatWeb.Utils, as: WebUtils
  alias Phoenix.HTML.Tag
  alias Phoenix.LiveView.JS

  attr :author, Card, doc: "message author card"
  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :dynamic_attrs, :list, doc: "HTML attributes for the message block"
  attr :export?, :boolean, default: false, doc: "hide options and set path for exported file"
  attr :is_mine?, :boolean, doc: "is current user the author of the message?"
  attr :me, Identity, doc: "current user - used only for :dialog chat type"
  attr :msg, :map, required: true, doc: "message struct"
  attr :my_id, :string, doc: "current user's ID - used only for :room chat type"
  attr :peer, Card, doc: "the other user - used only for :dialog chat type"
  attr :room, Room, default: nil, doc: "room access was requested to"
  attr :timezone, :string, required: true, doc: "needed to render the timestamp"
  attr :room_keys, :map, default: [], doc: "the list of room keys"

  def message_block(assigns) do
    assigns =
      assigns
      |> assign_new(:is_mine?, fn
        %{chat_type: :dialog, msg: msg} ->
          msg.is_mine?

        %{chat_type: :room, msg: msg, my_id: my_id} ->
          msg.author_key == my_id
      end)
      |> assign_new(:author, fn
        %{chat_type: :dialog, is_mine?: is_mine?, me: me, peer: peer} ->
          (is_mine? && Card.from_identity(me)) || peer

        %{chat_type: :room, msg: msg} ->
          User.by_id(msg.author_key)
      end)
      |> assign_new(:dynamic_attrs, fn
        %{export?: true} ->
          []

        %{chat_type: chat_type, export?: false, is_mine?: is_mine?, msg: msg} ->
          [
            phx_click:
              JS.dispatch("chat:select-message", detail: %{chatType: Atom.to_string(chat_type)}),
            phx_value_id: msg.id,
            phx_value_index: msg.index,
            phx_value_is_mine: Atom.to_string(is_mine?),
            phx_value_type: chat_type
          ]
      end)
      |> assign_file()

    ~H"""
    <div
      class="messageBlock flex flex-row px-2 sm:px-8"
      id={"message-block-#{@msg.id}"}
      data-type={@msg.type}
      {@dynamic_attrs}
    >
      <div
        class={"m-1 w-full flex " <> if(@is_mine?, do: "justify-end t-#{@chat_type}-mine-message x-mine", else: "justify-start x-peer")}
        id={"#{@chat_type}-message-#{@msg.id}"}
      >
        <.message
          author={@author}
          chat_type={@chat_type}
          color={if(@is_mine?, do: "bg-purple50", else: "bg-white")}
          export?={@export?}
          file={@file}
          is_mine?={@is_mine?}
          msg={@msg}
          receiver={assigns[:peer]}
          room={@room}
          room_keys={@room_keys}
          timezone={@timezone}
        />
      </div>

      <%= unless @export? do %>
        <input
          type="checkbox"
          class="selectCheckbox w-6 h-6 ml-3 mt-3 rounded-full text-purple/90 bg-black/10 border-gray-300 focus:ring-2 t-selectCheckbox"
        />
      <% end %>
    </div>
    """
  end

  attr :msg, :map, required: true, doc: "message struct"

  def text(%{msg: %{type: :memo}} = assigns) do
    assigns =
      assign_new(assigns, :memo, fn %{msg: %{content: json}} ->
        json
        |> StorageId.from_json()
        |> Memo.get()
      end)

    ~H"""
    <div class="px-4 w-full">
      <span class="flex-initial break-words">
        <%= nl2br(@memo) %>
      </span>
    </div>
    """
  end

  def text(%{msg: %{type: :text}} = assigns) do
    ~H"""
    <div class="px-4 w-full">
      <span class="flex-initial break-words">
        <%= nl2br(@msg.content) %>
      </span>
    </div>
    """
  end

  attr :author, Card, required: true, doc: "message author card"
  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :color, :string, required: true, doc: "color class - either bg-purple50 or bg-white"
  attr :export?, :boolean, required: true, doc: "hide options and set path for exported file"
  attr :file, :map, required: true, doc: "file map"
  attr :is_mine?, :boolean, required: true, doc: "is current user the author of the message?"
  attr :msg, :map, required: true, doc: "message struct"
  attr :receiver, Card, doc: "peer in dialog"
  attr :room, Room, default: nil, doc: "room access was requested to"
  attr :room_keys, :map, doc: "the list of room keys"
  attr :timezone, :string, required: true, doc: "needed to render the timestamp"

  defp message(%{msg: %{type: :audio}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
      phx-hook="AudioFile"
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
      />
      <.timestamp msg={@msg} timezone={@timezone} />
      <.audio export?={@export?} file={@file} msg={@msg} />
      <.media_file_info file={@file} />
    </div>
    """
  end

  defp message(%{msg: %{type: :file}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
      />
      <.file export?={@export?} file={@file} msg={@msg} />
      <.timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  defp message(%{msg: %{type: :image}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
      />
      <.timestamp msg={@msg} timezone={@timezone} />
      <.image chat_type={@chat_type} msg={@msg} export?={@export?} file={@file} />
      <.media_file_info file={@file} />
    </div>
    """
  end

  defp message(%{msg: %{type: type}} = assigns) when type in [:memo, :text] do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xs sm:max-w-md min-w-[180px] t-chat-mine-message rounded-lg shadow-lg"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
      />
      <span class="x-content"><.text msg={@msg} /></span>
      <.timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  defp message(%{msg: %{type: :request}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}
    >
      <div class="py-1 px-2">
        <Layout.Card.hashed_name card={@author} style_spec={:room_request_message} />
        <p class="inline-flex">requested access to room</p>
        <Layout.Card.hashed_name room={@room} style_spec={:room_request_message} />
      </div>
      <.timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  defp message(%{msg: %{type: :room_invite}} = assigns) do
    assigns =
      assigns
      |> assign_new(:room_card, fn
        %{msg: %{content: json}} ->
          json
          |> StorageId.from_json()
          |> RoomInvites.get()
          |> Identity.from_strings()
          |> Card.from_identity()
      end)

    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}
    >
      <div class="py-1 px-2">
        <%= if @is_mine? do %>
          <%= if @receiver == @author do %>
            <p class="inline-flex">You got the key copy of the room</p>
          <% else %>
            <Layout.Card.hashed_name card={@receiver} style_spec={:room_invite} />
            <p class="inline-flex">is invited by you into</p>
          <% end %>
        <% else %>
          <Layout.Card.hashed_name card={@author} style_spec={:room_invite} />
          <p class="inline-flex">wants you to join the room</p>
        <% end %>
        <Layout.Card.hashed_name room={@room_card} style_spec={:room_invite} />
      </div>

      <%= unless @export? do %>
        <%= if (@is_mine? and @author == @receiver) or not @is_mine? do %>
          <div
            data-room={Enigma.short_hash(@room_card)}
            class="x-invite-navigation flex flex-col sm:flex-row sm:items-center sm:justify-between px-2 my-1"
          >
            <.room_invite_navigation room_key={@room_card.pub_key} room_keys={@room_keys} msg={@msg} />
          </div>
        <% end %>
      <% end %>

      <.timestamp msg={@msg} timezone={@timezone} />
    </div>
    """
  end

  defp message(%{msg: %{type: :video}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
      />
      <.timestamp msg={@msg} timezone={@timezone} />
      <video src={@file[:url]} class="a-video" controls />
      <.media_file_info file={@file} />
    </div>
    """
  end

  defp message(assigns) do
    ["[message] ", "error rendering ", inspect(assigns[:msg], pretty: true)] |> Logger.warn()

    ~H"""
    <!-- error rendering message -->
    """
  end

  attr :author, Card, required: true, doc: "message author card"
  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :export?, :boolean, required: true, doc: "hide options and set path for exported file"
  attr :file, :map, required: true, doc: "file map"
  attr :is_mine?, :boolean, required: true, doc: "is current user the author of the message?"
  attr :msg, :map, required: true, doc: "message struct"

  defp header(assigns) do
    ~H"""
    <.header_wrapper
      class="py-1 px-2 flex items-center justify-between relative"
      id={"message-header-#{@msg.id}"}
      export?={@export?}
      file={@file}
      msg_type={@msg.type}
    >
      <.header_content
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
      />
    </.header_wrapper>
    """
  end

  attr :class, :string, doc: "header wrapper class"
  attr :export?, :boolean, required: true, doc: "hide options and set path for exported file"
  attr :file, :map, required: true, doc: "file map"
  attr :id, :string, doc: "header wrapper id"
  attr :msg_type, :atom, required: true, doc: "message type"
  slot :inner_block, required: true

  defp header_wrapper(%{export?: true, msg_type: type} = assigns) when type in [:audio, :video] do
    ~H"""
    <.link class={@class} id={@id} href={@file[:url]}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  defp header_wrapper(assigns) do
    ~H"""
    <div class={@class} id={@id}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp header_content(%{export?: true} = assigns) do
    ~H"""
    <Layout.Card.hashed_name card={@author} style_spec={:message_header} />
    """
  end

  defp header_content(assigns) do
    ~H"""
    <Layout.Card.hashed_name card={@author} style_spec={:message_header} />
    <button
      type="button"
      class="messageActionsDropdownButton hiddenUnderSelection t-message-dropdown"
      phx-click={
        open_dropdown("messageActionsDropdown-#{@msg.id}")
        |> JS.dispatch("chat:set-dropdown-position",
          to: "#messageActionsDropdown-#{@msg.id}",
          detail: %{relativeElementId: "message-#{@msg.id}"}
        )
      }
    >
      <.icon id="menu" class="w-4 h-4 flex fill-purple" />
    </button>
    <.dropdown class="messageActionsDropdown " id={"messageActionsDropdown-#{@msg.id}"}>
      <%= if @is_mine? do %>
        <%= if @msg.type in [:text, :memo] do %>
          <a
            class="dropdownItem t-edit-message"
            phx-click={
              hide_dropdown("messageActionsDropdown-#{@msg.id}")
              |> JS.push("#{@chat_type}/message/edit")
            }
            phx-value-id={@msg.id}
            phx-value-index={@msg.index}
          >
            <.icon id="edit" class="w-4 h-4 flex fill-black" />
            <span>Edit</span>
          </a>
        <% end %>
        <a
          class="dropdownItem t-delete-message"
          phx-click={
            hide_dropdown("messageActionsDropdown-#{@msg.id}")
            |> show_modal("delete-message-popup")
            |> JS.set_attribute(
              {"phx-click",
               hide_modal("delete-message-popup")
               |> JS.push("#{@chat_type}/delete-messages")
               |> stringify_commands()},
              to: "#delete-message-popup .deleteMessageButton"
            )
            |> JS.set_attribute(
              {"phx-value-messages", [%{id: @msg.id, index: "#{@msg.index}"}] |> Jason.encode!()},
              to: "#delete-message-popup .deleteMessageButton"
            )
          }
          phx-value-id={@msg.id}
          phx-value-index={@msg.index}
          phx-value-type="dialog-message"
        >
          <.icon id="delete" class="w-4 h-4 flex fill-black" />
          <span>Delete</span>
        </a>
      <% end %>
      <a phx-click={hide_dropdown("messageActionsDropdown-#{@msg.id}")} class="dropdownItem">
        <.icon id="share" class="w-4 h-4 flex fill-black" />
        <span>Share</span>
      </a>
      <a
        class="dropdownItem t-select-message"
        phx-click={
          hide_dropdown("messageActionsDropdown-#{@msg.id}")
          |> JS.push("#{@chat_type}/toggle-messages-select",
            value: %{action: :on, id: @msg.id, chatType: @chat_type}
          )
          |> JS.dispatch("chat:select-message",
            to: "#message-block-#{@msg.id}",
            detail: %{chatType: @chat_type}
          )
        }
      >
        <.icon id="select" class="w-4 h-4 flex fill-black" />
        <span>Select</span>
      </a>
      <%= if @msg.type in [:audio, :file, :image, :video] do %>
        <a
          class="dropdownItem"
          phx-click={
            hide_dropdown("messageActionsDropdown-#{@msg.id}")
            |> JS.push("#{@chat_type}/message/download")
          }
          phx-value-id={@msg.id}
          phx-value-index={@msg.index}
        >
          <.icon id="download" class="w-4 h-4 flex fill-black" />
          <span>Download</span>
        </a>
      <% end %>
    </.dropdown>
    """
  end

  attr :room_key, :string, required: true, doc: "room public key"
  attr :room_keys, :list, required: true, doc: "room_map keys"
  attr :msg, :map, required: true, doc: "message struct"

  def room_invite_navigation(assigns) do
    ~H"""
    <%= if @room_key in @room_keys do %>
      <button
        class="w-full h-12 border-0 rounded-lg bg-grayscale text-white"
        phx-click="dialog/message/accept-room-invite-and-open-room"
        phx-value-id={@msg.id}
        phx-value-index={@msg.index}
      >
        Go to Room
      </button>
    <% else %>
      <button
        class="w-full sm:w-[30%] h-12 border-0 rounded-lg bg-grayscale text-white mb-2 sm:mb-0 sm:mr-2"
        phx-click="dialog/message/accept-room-invite"
        phx-value-id={@msg.id}
        phx-value-index={@msg.index}
      >
        Accept
      </button>
      <button
        class="w-full sm:w-[40%] h-12 border-0 rounded-lg bg-grayscale text-white mb-2 sm:mb-0 sm:mr-2"
        phx-click="dialog/message/accept-room-invite-and-open-room"
        phx-value-id={@msg.id}
        phx-value-index={@msg.index}
      >
        Accept and Open
      </button>
      <button
        class="w-full sm:w-[30%] h-12 border-0 rounded-lg bg-grayscale text-white mb-2 sm:mb-0 sm:mr-2"
        phx-click="dialog/message/accept-all-room-invites"
      >
        Accept all
      </button>
    <% end %>
    """
  end

  attr :msg, :map, required: true, doc: "message struct"
  attr :timezone, :string, required: true, doc: "user's timezone"

  defp timestamp(assigns) do
    assigns =
      assign_new(assigns, :time, fn %{msg: %{timestamp: timestamp}, timezone: timezone} ->
        timestamp
        |> DateTime.from_unix!()
        |> DateTime.shift_zone!(timezone)
        |> Timex.format!("{h12}:{0m} {AM}, {D}.{M}.{YYYY}")
      end)

    ~H"""
    <div class="px-2 text-grayscale600 flex justify-end mr-1" style="font-size: 10px;">
      <%= @time %>
    </div>
    """
  end

  defp assign_file(%{export?: true, msg: %{content: json, type: type}} = assigns)
       when type in [:audio, :file, :image, :video] do
    {id, secret} = StorageId.from_json(json)
    [_, _, _, _, name, size] = Files.get(id, secret)

    filename = ExportHelper.get_filename(name, id)

    assign(assigns, :file, %{
      name: name,
      size: size,
      url: "files/" <> filename
    })
  end

  defp assign_file(%{msg: %{content: json, type: type}} = assigns) do
    with true <- type in [:audio, :image, :video, :file],
         {id, secret} <- StorageId.from_json(json),
         [_, _, _, _, name, size] <- Files.get(id, secret) do
      %{
        name: name,
        size: size,
        url: WebUtils.get_file_url(:file, id, secret)
      }
    else
      _ ->
        %{
          name: "Broken file",
          size: "n/a",
          url: nil
        }
    end
    |> then(&assign(assigns, :file, &1))
  end

  attr :export?, :boolean, required: true, doc: "embed file icon SVG?"
  attr :file, :map, required: true, doc: "file map"
  attr :msg, :map, required: true, doc: "message struct"

  defp file(assigns) do
    if assigns.file do
      ~H"""
      <.link class="flex items-center justify-between" href={@file.url}>
        <.file_icon export?={@export?} />

        <div class="w-36 flex flex-col pr-3">
          <span class="truncate text-xs x-file" href={@file.url}><%= @file.name %></span>
          <span class="text-xs text-black/50 whitespace-pre-line"><%= @file.size %></span>
        </div>
      </.link>
      """
    else
      ~H"""
      <div class="flex items-center justify-between">
        Error getting file
      </div>
      """
    end
  end

  attr :export?, :boolean, required: true, doc: "embed SVG?"

  defp file_icon(%{export?: true} = assigns) do
    ~H"""
    <svg
      id="document"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      class="w-14 h-14 flex fill-black/50"
    >
      <path
        fill-rule="evenodd"
        d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp file_icon(assigns) do
    ~H"""
    <.icon id="document" class="w-14 h-14 flex fill-black/50" />
    """
  end

  attr :file, :map, required: true, doc: "file map"

  defp media_file_info(assigns) do
    ~H"""
    <div class="w-full flex flex-row justify-between px-3 py-2">
      <span class="truncate text-xs x-file" href={@file.url}><%= @file.name %></span>
      <span class="text-xs text-black/50 whitespace-pre-line"><%= @file.size %></span>
    </div>
    """
  end

  attr :export?, :boolean, required: true, doc: "show waveform?"
  attr :file, :map, required: true, doc: "file map"
  attr :msg, :map, required: true, doc: "message struct"

  defp audio(%{export?: true} = assigns) do
    ~H"""
    <audio src={@file.url} class="a-audio" controls />
    """
  end

  defp audio(assigns) do
    ~H"""
    <div class="flex flex-row w-full h-12">
      <button class="play rounder flex justify-center items-center w-3/12">
        <svg class="pause-circle w-9 hidden" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">
          <path
            class="fill-purple"
            d="M24,4A20,20,0,1,0,44,24,20,20,0,0,0,24,4ZM21,33H16V15h5Zm11,0H27V15h5Z"
            transform="translate(-4 -4)"
          >
          </path>
        </svg>
        <svg class="play-circle w-9" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">
          <path
            class="fill-purple"
            d="M24,4A20,20,0,1,0,44,24,20,20,0,0,0,24,4ZM17,33V15l18,9Z"
            transform="translate(-4 -4)"
          >
          </path>
        </svg>
      </button>
      <div
        class="peaks-overview-container flex w-9/12 h-12"
        id={"message-#{@msg.id}-peaks"}
        phx-update="ignore"
      >
      </div>
    </div>
    <audio src={@file.url} class="a-audio hidden" controls />
    """
  end

  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :export?, :boolean, required: true, doc: "disable image gallery?"
  attr :file, :map, required: true, doc: "file map"
  attr :msg, :map, required: true, doc: "message struct"

  defp image(%{export?: true} = assigns) do
    ~H"""
    <.link href={@file.url}>
      <img class="object-cover overflow-hidden" src={@file.url} />
    </.link>
    """
  end

  defp image(assigns) do
    ~H"""
    <img
      class="object-cover overflow-hidden"
      src={@file[:url]}
      phx-click={open_gallery(@chat_type)}
      phx-value-id={@msg.id}
      phx-value-index={@msg.index}
    />
    """
  end

  defp open_gallery(chat_type, js \\ %JS{}) do
    js
    |> JS.push("#{chat_type}/message/open-image-gallery")
    |> JS.add_class("hidden", to: "#chatContent")
    |> JS.remove_class("hidden", to: "#imageGallery")
  end

  defp nl2br(str), do: Utils.trim_text(str) |> Enum.intersperse(Tag.tag(:br))
end
