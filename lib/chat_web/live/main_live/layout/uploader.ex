defmodule ChatWeb.MainLive.Layout.Uploader do
  @moduledoc """
  Uploader layout
  Used for rendering list of uploaded files, file upload form,
  and upload in progress indicator in dialogs and rooms.
  """

  use ChatWeb, :component

  alias Chat.Upload.UploadMetadata
  alias Phoenix.LiveView.{JS, UploadConfig, UploadEntry}

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :uploads, :map, required: true, doc: "uploads metadata"

  def uploader(assigns) do
    ~H"""
    <div class="flex fixed bottom-[-10px] w-[18%] left-30 flex-col mb-auto m-2" id="file-uploader">
      <.entries config={@config} uploads={@uploads} />
    </div>
    """
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :operating_system, :string, doc: "client's operating system"
  attr :uploads, :map, required: true, doc: "uploads metadata"

  def mobile_uploader(assigns) do
    ~H"""
    <div
      class="flex flex-col m-2 bg-purple50 rounded-lg"
      id="mobile-file-uploader"
      style="display: none;"
    >
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

  defp entries(%{uploads: uploads} = assigns) when map_size(uploads) > 0 do
    ~H"""
    <div class="px-2 py-1">
      <%= for %UploadEntry{valid?: true} = entry <- @config.entries do %>
        <.entry entry={entry} metadata={@uploads[entry.uuid]} mobile?={@mobile?} />
      <% end %>
    </div>
    """
  end

  defp entries(assigns) do
    ~H"""

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
      class="flex mb-5 bg-white border-purple relative w-full z-0"
      id={if(@mobile?, do: "mobile-", else: "") <> "upload-#{@entry.uuid}"}
    >
      <div
        class="absolute top-[-13px] left-0 h-3 bg-gray-500 z-10 transition-all"
        style={"width: #{@entry.progress}%;"}
      >
      </div>
      <div class="flex flex-row w-full p-2 items-center justify-between z-20 text-black/50">
        <div class="flex text-xs min-w-[20%] max-w-[50%]">
          <span class="truncate"><%= @entry.client_name %></span>
        </div>
        <div class="flex text-xs text-black/50"><%= @entry.progress %>%</div>

        <%= if @metadata.status == :active do %>
          <.upload_control phx-click="upload:pause" phx-value-uuid={@entry.uuid}>
            Pause
          </.upload_control>
        <% else %>
          <.upload_control phx-click="upload:resume" phx-value-uuid={@entry.uuid}>
            Resume
          </.upload_control>
        <% end %>
        <.upload_control
          phx-click="upload:cancel"
          phx-value-ref={@entry.ref}
          phx-value-uuid={@entry.uuid}
        >
          Cancel
        </.upload_control>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil, doc: "classes to append"
  attr :rest, :global, doc: "rest of the attrs"
  slot :inner_block, required: true

  defp upload_control(assigns) do
    ~H"""
    <.link class={"flex text-xs" <> if(@class, do: " #{@class}", else: "")} href="#" {@rest}>
      <%= render_slot(@inner_block) %>
    </.link>
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
      class="flex flex-col m-2 column column-50 column-offset-50"
      phx-drop-target={@config.ref}
    >
      <.live_file_input
        class="file-input block p-2 flex flex-col items-center text-sm text-black/50 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-purple file:text-purple50 file:cursor-pointer"
        upload={@config}
      />

      <%= if @operating_system == "Android" do %>
        <input
          accept="audio/*,image/*,video/*"
          class="block p-2 flex flex-col items-center text-sm text-black/50 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-purple file:text-purple50 file:cursor-pointer"
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
      <div class="flex flex-row justify-end" id="upload-in-progress" phx-hook="UploadInProgress">
        <div class="m-1 sm:mx-8 bg-purple50 rounded-lg shadow-lg inline-flex items-center px-4 py-2 font-semibold leading-6 text-sm text-black/50 shadow transition ease-in-out duration-150">
          <svg
            class="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle class="opacity-50" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
            </circle>
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            >
            </path>
          </svg>
          Upload in progress...
        </div>
      </div>
    <% end %>
    """
  end
end
