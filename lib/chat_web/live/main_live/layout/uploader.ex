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

  def uploader(assigns) do
    ~H"""
    <div id="file-uploader">
      <.entries config={@config} uploads={@uploads} />
    </div>
    """
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :operating_system, :string, doc: "client's operating system"
  attr :uploads, :map, required: true, doc: "uploads metadata"

  def mobile_uploader(assigns) do
    ~H"""
    <div id="mobile-file-uploader" style="display: none;">
      <.file_form config={@config} operating_system={@operating_system} />

      <.entries config={@config} mobile?={true} uploads={@uploads} />
    </div>
    """
  end

  attr :type, :string, required: true, doc: "dialog or room"

  def button(assigns) do
    ~H"""
    <div id="uploader-button">
      <button
        class="hidden sm:block relative t-attach-file"
        phx-click={open_file_upload_dialog(@type)}
      >
        <.icon id="attach" class="w-7 h-7 flex fill-white" />
      </button>

      <button class="sm:hidden relative t-attach-file" phx-click={toggle_uploader(@type)}>
        <.icon id="attach" class="w-7 h-7 flex fill-white" />
      </button>
    </div>
    """
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :mobile?, :boolean, default: false, doc: "whether it's a mobile file uploader"
  attr :uploads, :map, required: true, doc: "uploads metadata"

  defp entries(assigns) do
    ~H"""
    <%= for %UploadEntry{valid?: true} = entry <- @config.entries do %>
      <.entry entry={entry} metadata={@uploads[entry.uuid]} mobile?={@mobile?} />
    <% end %>
    """
  end

  attr :entry, UploadEntry, required: true, doc: "upload entry"
  attr :mobile?, :boolean, required: true
  attr :metadata, UploadMetadata, doc: "upload metadata"

  defp entry(%{metadata: nil} = assigns) do
    ~H"""

    """
  end

  defp entry(assigns) do
    ~H"""
    <div
      class="m-1 flex justify-end"
      id={if(@mobile?, do: "mobile-", else: "") <> "upload-#{@entry.uuid}"}
    >
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

  defp open_file_upload_dialog(type) do
    %JS{}
    |> JS.set_attribute({"phx-change", "#{type}/import-files"}, to: "#uploader-file-form")
    |> JS.dispatch("click", to: "#uploader-file-form .file-input")
  end

  defp toggle_uploader(type) do
    %JS{}
    |> JS.set_attribute({"phx-change", "#{type}/import-files"}, to: "#uploader-file-form")
    |> JS.toggle(to: "#mobile-file-uploader")
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :operating_system, :string, doc: "client's operating system"

  defp file_form(assigns) do
    ~H"""
    <.form
      for={:file}
      id="uploader-file-form"
      class="column column-50 column-offset-50"
      phx-drop-target={@config.ref}
    >
      <.live_file_input class="file-input" upload={@config} />

      <%= if @operating_system == "Android" do %>
        <input
          accept="audio/*,image/*,video/*"
          data-ref={@config.ref}
          id={"#{@config.ref}-android"}
          phx-hook="AndroidMediaFileInput"
          type="file"
          multiple={if(@config.max_entries > 1, do: true)}
        />
      <% end %>
    </.form>
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
