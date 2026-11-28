defmodule ChatWeb.MainLive.Layout.Message.Header do
  @moduledoc "Message header (author, actions dropdown), timestamp and link indicator."
  use ChatWeb, :component

  alias Chat.Card
  alias ChatWeb.MainLive.Layout
  alias Phoenix.LiveView.JS

  attr :author, Card, required: true, doc: "message author card"
  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :export?, :boolean, required: true, doc: "hide options and set path for exported file"
  attr :file, :map, required: true, doc: "file map"
  attr :is_mine?, :boolean, required: true, doc: "is current user the author of the message?"
  attr :msg, :map, required: true, doc: "message struct"
  attr :linkable?, :boolean, default: false, doc: "linkable? Only for public rooms"

  def header(assigns) do
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
        linkable?={@linkable?}
      />
    </.header_wrapper>
    """
  end

  attr :msg, :map, required: true, doc: "message struct"

  def timestamp(assigns) do
    ~H"""
    <div class="px-2 text-grayscale600 flex justify-end mr-1" style="font-size: 10px;">
      <.vue v-component="LocalTimestamp" unixtime={@msg.timestamp} />
    </div>
    """
  end

  def message_link(assigns) do
    ~H"""
    <div class="link-status">
      <%= if @linked do %>
        <a
          phx-click="room/message/share-link-modal"
          phx-value-id={@msg_id}
          phx-value-index={@msg_index}
        >
          <.icon id="link" class="w-3 h-3 fill-black/50 stroke-black stroke-2" />
        </a>
      <% end %>
    </div>
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
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp header_wrapper(assigns) do
    ~H"""
    <div class={@class} id={@id}>
      {render_slot(@inner_block)}
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
    <Layout.Card.hashed_name card={@author} style_spec={:message_header} show_link?={true} />
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
      <%= if @linkable? do %>
        <a
          class="dropdownItem t-link-action"
          phx-click={
            hide_dropdown("messageActionsDropdown-#{@msg.id}") |> JS.push("room/message/link")
          }
          phx-value-id={@msg.id}
          phx-value-index={@msg.index}
        >
          <.icon id="link" class="w-4 h-4 flex fill-black stroke-black stroke-2" />
          <span>Link</span>
        </a>
      <% end %>
    </.dropdown>
    """
  end
end
