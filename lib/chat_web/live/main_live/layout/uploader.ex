defmodule ChatWeb.MainLive.Layout.Uploader do
  @moduledoc """
  Uploader layout
  Used for rendering list of uploaded files, file upload form,
  and upload in progress indicator in dialogs and rooms.
  """

  use ChatWeb, :component

  alias Chat.UploadMetadata
  alias Phoenix.LiveView.{JS, UploadConfig, UploadEntry}

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :uploads, :map, required: true, doc: "uploads metadata"

  def list(assigns) do
    ~H"""
    <%= for %UploadEntry{valid?: true} = entry <- @config.entries do %>
      <.entry entry={entry} metadata={@uploads[entry.uuid]} />
    <% end %>
    """
  end

  attr :entry, UploadEntry, required: true, doc: "upload entry"
  attr :metadata, UploadMetadata, doc: "upload metadata"

  defp entry(%{metadata: nil} = assigns) do
    ~H"""

    """
  end

  defp entry(assigns) do
    ~H"""
    <div id={"upload-#{@entry.uuid}"} class="m-1 flex justify-end">
      <div class="bg-purple50 max-w-xxs sm:max-w-md min-w-[180px] rounded-lg flex items-center justify-between">
        <div class="w-36 flex flex-col pr-3">
          <span class="truncate text-xs"><%= @entry.client_name %></span>
          <div class="text-xs text-black/50">
            <%= @entry.progress %>%
          </div>

          <%= if @metadata.status == :active do %>
            <.link href="#" phx-click="upload:pause" phx-value-uuid={@entry.uuid}>Pause</.link>
          <% else %>
            <.link href="#" phx-click="upload:resume" phx-value-uuid={@entry.uuid}>Resume</.link>
          <% end %>
          <.link
            href="#"
            phx-click="upload:cancel"
            phx-value-ref={@entry.ref}
            phx-value-uuid={@entry.uuid}
          >
            Cancel
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :type, :string, required: true, doc: "dialog or room"

  def file_form(assigns) do
    ~H"""
    <.form
      for={:file}
      id="file-form"
      class="column column-50 column-offset-50"
      phx-change={"#{@type}/import-files"}
      phx-drop-target={@config.ref}
    >
      <%= live_file_input(@config, style: "display: none") %>
    </.form>

    <button
      class="relative t-attach-file"
      id="attachFileBtn"
      phx-click={JS.dispatch("click", to: "#file-form input[type=file]")}
    >
      <.icon id="attach" class="w-7 h-7 flex fill-white" />
    </button>
    """
  end

  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :uploads, :map, required: true, doc: "uploads metadata"
  attr :type, :atom, required: true, doc: ":dialog or :room"

  def in_progress?(assigns) do
    ~H"""
    <%= if Enum.any?(@uploads, fn {_uuid, %UploadMetadata{} = metadata} -> metadata.destination.type == @type and metadata.destination.pub_key == @pub_key end) do %>
      Upload in progress
    <% end %>
    """
  end
end
