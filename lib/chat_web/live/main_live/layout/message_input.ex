defmodule ChatWeb.MainLive.Layout.MessageInput do
  @moduledoc "Message input rendering component"
  use ChatWeb, :component

  alias ChatWeb.MainLive.Layout
  alias Phoenix.LiveView.JS

  attr :type, :string, required: true, doc: "dialog or room type"
  attr :input_mode, :atom, doc: "one of [:plain, :edit, :select]"
  attr :edit_content, :string, doc: "text to edit"

  def render(%{type: "dialog"} = assigns) do
    ~H"""
    <div
      id="dialogInput"
      class="basis-[7%] w-full py-1.5 px-8 border border-white bg-white flex items-center fixed md:sticky bottom-0"
    >
      <%= if @input_mode == :plain do %>
        <Layout.Uploader.button type={@type} />
        <.form
          :let={di}
          for={:dialog}
          id="dialog-form"
          class="basis-[99%] flex items-center justify-between"
          phx-change={JS.dispatch("chat:set-input-size", to: "#dialog-input")}
          phx-submit={
            JS.push("dialog/text-message")
            |> JS.dispatch("chat:clear-value", to: "#dialog-input")
            |> JS.dispatch("chat:set-input-size", to: "#dialog-input")
          }
          onkeydown="if (!event.shiftKey && !event.ctrlKey && event.key == 'Enter') {
                      document.getElementById('dialog-form-submit-button').click()
                    }"
        >
          <%= textarea(di, :text,
            placeholder: "Enter message",
            class:
              "w-full h-10 resize-none border-0 overflow-y-auto text-black placeholder-black/50 focus:ring-0 t-chat-input",
            id: "dialog-input",
            spellcheck: "false",
            autocomplete: "off"
          ) %>
          <button id="dialog-form-submit-button" class="t-chat-send-message-btn" type="submit">
            <.icon id="send" class="w-7 h-7 flex fill-purple" />
          </button>
        </.form>
      <% end %>
      <%= if @input_mode == :edit do %>
        <div class="w-full flex flex-col ">
          <div class="flex items-center justify-between pb-2 mt-2">
            <div class="w-[70vw]">
              <h1 class="text-purple t-edit">Editing</h1>
              <span class="truncate block text-xs text-black/50">
                <%= @edit_content %>
              </span>
            </div>
            <button type="button" class="t-cancel-edit" phx-click="dialog/cancel-edit">
              <.icon id="close" class="w-7 h-7 flex fill-black/50" />
            </button>
          </div>
          <.form
            :let={dei}
            for={:dialog_edit}
            id="dialog-edit-form"
            class="flex items-center justify-start "
            phx-change={JS.dispatch("chat:set-input-size", to: "#dialog-edit-input")}
            phx-submit={
              JS.push("dialog/edited-message")
              |> JS.dispatch("chat:clear-value", to: "#dialog-edit-input")
              |> JS.dispatch("chat:set-input-size", to: "#dialog-edit-input")
            }
            onkeydown="
                      if (event.key == 'Enter' && event.shiftKey) {
                        document.getElementById('dialog-edit-form-submit-button').click()
                      }
                      "
          >
            <%= textarea(dei, :text,
              class:
                "w-full px-0 resize-none outline-none border-0 overflow-scroll text-black placeholder-black/50 focus:ring-0 t-chat-edit-input",
              id: "dialog-edit-input",
              spellcheck: "false",
              autocomplete: "off",
              value: @edit_content
            ) %>
            <button id="dialog-edit-form-submit-button" class="t-chat-edit-send-btn" type="submit">
              <.icon id="send" class="w-7 h-7 flex fill-purple" />
            </button>
          </.form>
        </div>
      <% end %>
      <%= if @input_mode == :select do %>
        <div class="w-full h-11 bg-white flex justify-between items-center">
          <button
            id="delete-btn"
            class="cursor-pointer inline-flex items-center disabled:pointer-events-none t-delete-chat-msg-btn"
            phx-click={
              show_modal("delete-messages-popup")
              |> JS.set_attribute(
                {"phx-click",
                 hide_modal("delete-messages-popup")
                 |> JS.push("dialog/delete-messages")
                 |> stringify_commands()},
                to: "#delete-messages-popup .deleteMessageButton"
              )
              |> JS.dispatch("chat:messages-to-delete", to: "#delete-messages-popup")
            }
          >
            <.icon id="delete" class="w-4 h-4 flex fill-black x-icon" />
            <span id="delete-span">Delete</span>
          </button>

          <button
            id="download-btn"
            class="cursor-pointer inline-flex items-center t-download-chat-msg-btn"
            phx-click={
              JS.dispatch("chat:download-messages",
                to: "#chatContent",
                detail: %{chatType: "dialog"}
              )
            }
          >
            <span class="text-purple">Download</span>
            <.icon id="download" class="ml-1 w-4 h-4 flex  stroke-purple " />
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  def render(%{type: "room"} = assigns) do
    ~H"""
    <div class="basis-[7%] w-full py-1.5 px-8 border border-white bg-white flex items-center fixed md:sticky bottom-0">
      <%= if @input_mode == :plain do %>
        <Layout.Uploader.button type={@type} />
        <.form
          :let={di}
          for={:room}
          id="room-form"
          class="basis-[99%] flex items-center justify-between"
          phx-change={JS.dispatch("chat:set-input-size", to: "#room-input")}
          phx-submit={
            JS.push("room/text-message")
            |> JS.dispatch("chat:clear-value", to: "#room-input")
            |> JS.dispatch("chat:set-input-size", to: "#room-input")
          }
          onkeydown="if (!event.shiftKey && !event.ctrlKey && event.key == 'Enter') {
                      document.getElementById('room-form-submit-button').click()
                    }"
        >
          <%= textarea(di, :text,
            placeholder: "Enter message",
            class:
              "w-full h-10 resize-none border-0 overflow-y-auto text-black placeholder-black/50 focus:ring-0 t-room-input",
            id: "room-input",
            spellcheck: "false",
            autocomplete: "off"
          ) %>
          <button id="room-form-submit-button" class="t-room-send-message-btn" type="submit">
            <.icon id="send" class="w-7 h-7 flex fill-purple" />
          </button>
        </.form>
      <% end %>
      <%= if @input_mode == :edit do %>
        <div class="w-full flex flex-col ">
          <div class="flex items-center justify-between pb-2 mt-2">
            <div class="w-[95%]">
              <h1 class="text-purple t-edit">Editing</h1>
              <span class="truncate block text-xs text-black/50">
                <%= @edit_content %>
              </span>
            </div>
            <button type="button" class="t-cancel-edit" phx-click="room/cancel-edit">
              <.icon id="close" class="w-7 h-7 flex fill-black/50" />
            </button>
          </div>
          <.form
            :let={dei}
            for={:room_edit}
            id="rooom-edit-form"
            class="flex items-center justify-start "
            phx-change={JS.dispatch("chat:set-input-size", to: "#room-input")}
            phx-submit={
              JS.push("room/edited-message")
              |> JS.dispatch("chat:clear-value", to: "#room-input")
              |> JS.dispatch("chat:set-input-size", to: "#room-input")
            }
            onkeydown="
                      if (event.key == 'Enter' && event.shiftKey) {
                        document.getElementById('room-edit-form-submit-button').click()
                      }
                      "
          >
            <%= textarea(dei, :text,
              class:
                "w-full px-0 resize-none outline-none border-0 overflow-scroll text-black placeholder-black/50 focus:ring-0 t-room-edit-input",
              id: "room-edit-input",
              spellcheck: "false",
              autocomplete: "off",
              value: @edit_content
            ) %>
            <button id="room-edit-form-submit-button" type="submit">
              <.icon id="send" class="w-7 h-7 flex fill-purple t-room-edit-send-btn" />
            </button>
          </.form>
        </div>
      <% end %>
      <%= if @input_mode == :select do %>
        <div class="w-full h-11 bg-white flex justify-between items-center">
          <button
            id="delete-btn"
            class="cursor-pointer inline-flex items-center disabled:pointer-events-none t-delete-room-msg-btn"
            phx-click={
              show_modal("delete-messages-popup")
              |> JS.set_attribute(
                {"phx-click",
                 hide_modal("delete-messages-popup")
                 |> JS.push("room/delete-messages")
                 |> stringify_commands()},
                to: "#delete-messages-popup .deleteMessageButton"
              )
              |> JS.dispatch("chat:messages-to-delete", to: "#delete-messages-popup")
            }
          >
            <.icon id="delete" class="w-4 h-4 flex fill-black x-icon" />
            <span id="delete-span">Delete</span>
          </button>

          <button
            id="download-btn"
            class="cursor-pointer inline-flex items-center t-download-room-msg-btn"
            phx-click={
              JS.dispatch("chat:download-messages",
                to: "#chatContent",
                detail: %{chatType: "room"}
              )
            }
          >
            <span class="text-purple">Download</span>
            <.icon id="download" class="ml-1 w-4 h-4 flex  stroke-purple " />
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
