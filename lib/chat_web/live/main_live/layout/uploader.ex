defmodule ChatWeb.MainLive.Layout.Uploader do
  @moduledoc """
  Uploader layout
  Used for rendering list of uploaded files, file upload form,
  and upload in progress indicator in dialogs and rooms.
  """

  use ChatWeb, :component

  import ChatWeb.MainLive.Layout.Uploader.Entries, only: [entries: 1]

  alias Chat.Upload.UploadMetadata
  alias Phoenix.LiveView.{JS, UploadConfig, UploadEntry}

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :type, :atom, required: true, doc: ":dialog or :room"
  attr :uploads, :map, required: true, doc: "uploads metadata"
  attr :uploads_order, :list, required: true, doc: "uploads order"

  def uploader(assigns) do
    ~H"""
    <div
      class={
        classes(
          "flex flex-col-reverse w-full flex-col md:bottom-[-10px] md:w-[320px] md:left-[78px] overflow-scroll a-uploader",
          %{"hidden" => @uploads == %{}}
        )
      }
      id="file-uploader"
    >
      <.entries
        config={@config}
        pub_key={@pub_key}
        type={@type}
        uploads={@uploads}
        uploads_order={@uploads_order}
      />
    </div>
    """
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :operating_system, :string, doc: "client's operating system"
  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :type, :string, required: true, doc: "dialog or room"
  attr :uploads, :map, required: true, doc: "uploads metadata"
  attr :uploads_order, :list, required: true, doc: "uploads order"

  def mobile_uploader(assigns) do
    assigns =
      assign_new(assigns, :active?, fn %{config: %UploadConfig{} = config} ->
        Enum.any?(config.entries, fn %UploadEntry{} = entry ->
          entry.valid? and not (entry.done? or entry.cancelled?)
        end)
      end)

    ~H"""
    <div class="max-h-[280px] bottom-16 fixed sm:relative sm:bottom-0 w-full overflow-y-scroll flex flex-col-reverse a-mobile-uploader">
      <div class="h-full">
        <div
          class="flex flex-col m-2 bg-purple50 rounded-lg h-fit overflow-scroll sm:hidden"
          id="mobile-file-uploader"
          style={if(!@active?, do: "display: none;")}
        >
          <.file_form config={@config} operating_system={@operating_system} type={@type} />

          <.entries
            config={@config}
            mobile?={true}
            pub_key={@pub_key}
            type={String.to_existing_atom(@type)}
            uploads={@uploads}
            uploads_order={@uploads_order}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :enabled, :boolean, default: true, doc: "to allow or to restrict upload"
  attr :operating_system, :string, doc: "client's operating system"
  attr :type, :string, required: true, doc: "dialog or room"

  def button(assigns) do
    ~H"""
    <div id="uploader-button">
      <%= if @operating_system == "Android" do %>
        <button
          class="relative t-attach-file"
          phx-click={if @enabled, do: toggle_uploader(), else: show_modal("restrict-write-actions")}
        >
          <.icon
            id="attach"
            class={
              classes("w-7 h-7 flex", %{"fill-red-500" => !@enabled, "fill-gray-400" => @enabled})
            }
          />
        </button>
      <% else %>
        <button
          class="relative t-attach-file"
          phx-click={
            if @enabled,
              do: open_file_upload_dialog(),
              else: show_modal("restrict-write-actions")
          }
        >
          <.icon
            id="attach"
            class={
              classes("w-7 h-7 flex", %{"fill-red-500" => !@enabled, "fill-gray-400" => @enabled})
            }
          />
        </button>
      <% end %>
    </div>
    """
  end

  defp open_file_upload_dialog do
    JS.dispatch("click", to: "#uploader-file-form .file-input")
  end

  defp toggle_uploader do
    JS.toggle(to: "#mobile-file-uploader")
  end

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :operating_system, :string, doc: "client's operating system"
  attr :type, :string, required: true, doc: "dialog or room"

  defp file_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      as={:file}
      id="uploader-file-form"
      class="flex flex-col m-2 column column-50 column-offset-50"
      phx-change={"#{@type}/import-files"}
      phx-drop-target={@config.ref}
    >
      <.live_file_input
        class="file-input hidden p-1 flex flex-col items-center text-sm text-black/50 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-purple file:text-purple50 file:cursor-pointer"
        upload={@config}
      />

      <%= if @operating_system == "Android" do %>
        <div class="flex flex-row justify-around">
          <a
            class="flex justify-center items-center h-11 w-[30%] pr-2 cursor-pointer rounded-md bg-white hover:bg-white/50"
            phx-click={open_file_selector("*/*", "#uploader-file-form .file-input")}
          >
            <.icon id="document" class="w-4 h-4 fill-grayscale" />
            <span class="ml-2">File</span>
          </a>
          <a
            class="flex justify-center items-center h-11 w-[30%] pr-2 cursor-pointer rounded-md bg-white hover:bg-white/50"
            phx-click={open_file_selector("image/*, video/*", "#uploader-file-form .file-input")}
          >
            <.icon id="image" class="w-4 h-4 fill-grayscale" />
            <span class="ml-2">Image</span>
          </a>
          <a
            class="flex justify-center items-center h-11 w-[30%] pr-2 cursor-pointer rounded-md bg-white"
            phx-click={open_file_selector("audio/*", "#uploader-file-form .file-input")}
          >
            <.icon id="audio" class="w-4 h-4 fill-grayscale" />
            <span class="ml-2">Audio</span>
          </a>
        </div>
      <% end %>
    </.form>
    """
  end

  defp open_file_selector(media_type, dom_selector) do
    %JS{}
    |> JS.set_attribute({"accept", media_type}, to: dom_selector)
    |> JS.dispatch("click", to: dom_selector)
  end

  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :uploads, :map, required: true, doc: "uploads metadata"
  attr :type, :atom, required: true, doc: ":dialog or :room"

  def in_progress?(assigns) do
    ~H"""
    <%= if Enum.any?(@uploads, fn {_uuid, %UploadMetadata{} = metadata} -> metadata.destination.type == @type and metadata.destination.pub_key == @pub_key end) do %>
      <div
        class="hidden flex-row justify-end md:flex"
        id="upload-in-progress"
        phx-hook="UploadInProgress"
      >
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
