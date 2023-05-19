defmodule ChatWeb.MainLive.Layout.Uploader do
  @moduledoc """
  Uploader layout
  Used for rendering list of uploaded files, file upload form,
  and upload in progress indicator in dialogs and rooms.
  """

  use ChatWeb, :component

  alias Chat.Upload.UploadMetadata
  alias Phoenix.LiveView.{JS, UploadConfig, UploadEntry, Utils}

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
    <div class="max-h-[280px] bottom-16 fixed w-full overflow-y-scroll flex flex-col-reverse a-mobile-uploader">
      <div class="h-full">
        <div
          class="flex flex-col m-2 bg-purple50 rounded-lg h-fit overflow-scroll sm:hidden"
          id="mobile-file-uploader"
          style={unless(@active?, do: "display: none;")}
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

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :enabled, :boolean, default: true, doc: "to allow or to restrict upload"
  attr :type, :string, required: true, doc: "dialog or room"

  def push_to_talk_button(assigns) do
    ~H"""
    <div class="flex flex-row items-center">
      <button
        class="cursor-pointer mr-2"
        id="push-to-talk-button"
        phx-click={
          if(@enabled, do: open_audio_file_upload_dialog(), else: show_modal("restrict-write-actions"))
        }
      >
        <svg class="w-7 h-7 p-1 bg-purple rounded-full fill-white" viewbox="0 0 490.9 490.9">
          <g class="start">
            <path d="M245.5,322.9c53,0,96.2-43.2,96.2-96.2V96.2c0-53-43.2-96.2-96.2-96.2s-96.2,43.2-96.2,96.2v130.5
            C149.3,279.8,192.5,322.9,245.5,322.9z M173.8,96.2c0-39.5,32.2-71.7,71.7-71.7s71.7,32.2,71.7,71.7v130.5
            c0,39.5-32.2,71.7-71.7,71.7s-71.7-32.2-71.7-71.7V96.2z" />
            <path d="M94.4,214.5c-6.8,0-12.3,5.5-12.3,12.3c0,85.9,66.7,156.6,151.1,162.8v76.7h-63.9c-6.8,0-12.3,5.5-12.3,12.3
            s5.5,12.3,12.3,12.3h152.3c6.8,0,12.3-5.5,12.3-12.3s-5.5-12.3-12.3-12.3h-63.9v-76.7c84.4-6.3,151.1-76.9,151.1-162.8
            c0-6.8-5.5-12.3-12.3-12.3s-12.3,5.5-12.3,12.3c0,76.6-62.3,138.9-138.9,138.9s-138.9-62.3-138.9-138.9
            C106.6,220,101.2,214.5,94.4,214.5z" />
          </g>

          <g class="stop hidden">
            <rect width="300.9" height="300.9" rx="25" x="100" y="100" />
          </g>
        </svg>
      </button>
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

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :mobile?, :boolean, default: false, doc: "whether it's a mobile file uploader"
  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :type, :atom, required: true, doc: ":dialog or :room"
  attr :uploads, :map, required: true, doc: "uploads metadata"
  attr :uploads_order, :list, required: true, doc: "uploads order"

  defp entries(%{uploads: uploads} = assigns) when map_size(uploads) > 0 do
    ~H"""
    <div
      class="p-2"
      id={Utils.random_id()}
      phx-mounted={JS.dispatch("phx:scroll-uploads-to-top")}
      phx-hook="SortableUploadEntries"
    >
      <%= for uuid <- @uploads_order do %>
        <.entry
          entry={Enum.find(@config.entries, &(&1.uuid == uuid and &1.valid?))}
          metadata={@uploads[uuid]}
          mobile?={@mobile?}
          pub_key={@pub_key}
          type={@type}
        />
      <% end %>
    </div>
    """
  end

  defp entries(assigns) do
    ~H"""

    """
  end

  attr :entry, UploadEntry, doc: "upload entry"
  attr :mobile?, :boolean, required: true
  attr :metadata, UploadMetadata, doc: "upload metadata"
  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :type, :atom, required: true, doc: ":dialog or :room"

  defp entry(%{entry: entry, metadata: metadata} = assigns)
       when is_nil(entry) or is_nil(metadata) do
    ~H"""

    """
  end

  defp entry(assigns) do
    ~H"""
    <div
      class={"flex mb-2 border-purple relative w-full z-0 " <> if(@metadata.destination.type == @type and @metadata.destination.pub_key == @pub_key |> Base.encode16(case: :lower), do: "bg-white", else: "bg-pink-100")}
      id={if(@mobile?, do: "mobile-", else: "") <> "upload-#{@entry.uuid}"}
      data-uuid={@entry.uuid}
    >
      <div
        class="absolute top-[-13px] left-0 h-3 bg-gray-500 z-10 transition-all"
        style={"width: #{@entry.progress}%;"}
      >
      </div>

      <div class="flex flex-row w-full p-2 items-center justify-between z-20 text-black/50">
        <div class="sorting-handle flex cursor-pointer w-[70%]">
          <div class="flex justify-center items-center w-4 h-4">
            <svg viewBox="0 0 100 80" width="40" height="40">
              <rect width="100" height="20" rx="8"></rect>
              <rect y="30" width="100" height="20" rx="8"></rect>
              <rect y="60" width="100" height="20" rx="8"></rect>
            </svg>
          </div>

          <div class="flex text-xs ml-2 min-w-[20%] max-w-[50%]">
            <span class="truncate"><%= @entry.client_name %></span>
          </div>

          <div class="flex text-xs ml-auto text-black/50"><%= @entry.progress %>%</div>
        </div>

        <%= if @metadata.status == :active do %>
          <.upload_control phx-click={pause_upload(@entry.uuid)}>
            Pause
          </.upload_control>
        <% else %>
          <.upload_control phx-click={resume_upload(@entry.uuid)}>
            <%= if @metadata.status == :pending do %>
              Start
            <% else %>
              Resume
            <% end %>
          </.upload_control>
        <% end %>
        <.upload_control phx-click={cancel_upload(@entry.uuid, @entry.ref)}>
          Cancel
        </.upload_control>
      </div>
    </div>
    """
  end

  defp cancel_upload(uuid, ref) do
    %JS{}
    |> JS.dispatch("upload:cancel", detail: %{uuid: uuid})
    |> JS.push("upload:cancel", value: %{"ref" => ref, "uuid" => uuid})
  end

  defp pause_upload(uuid) do
    %JS{}
    |> JS.dispatch("upload:pause", detail: %{uuid: uuid})
    |> JS.push("upload:pause", value: %{"uuid" => uuid})
  end

  defp resume_upload(uuid) do
    JS.push("upload:resume", value: %{"uuid" => uuid})
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

  defp open_audio_file_upload_dialog do
    JS.dispatch("click", to: "#uploader-file-form .audio-file-input")
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

      <input
        accept="audio/*"
        class="audio-file-input hidden"
        data-ref={@config.ref}
        id={"#{@config.ref}-push-to-talk"}
        name="audio_file"
        phx-hook="MediaFileInput"
        type="file"
        multiple={if(@config.max_entries > 1, do: true)}
      />

      <%= if @operating_system == "Android" do %>
        <div class="flex flex-row justify-around">
          <a
            class="flex justify-center items-center h-11 w-[30%] pr-2 cursor-pointer rounded-md bg-white hover:bg-white/50"
            phx-click={JS.dispatch("click", to: "#uploader-file-form .file-input")}
          >
            <.icon id="document" class="w-4 h-4 fill-grayscale" />
            <span class="ml-2">File</span>
          </a>
          <a
            class="flex justify-center items-center h-11 w-[30%] pr-2 cursor-pointer rounded-md bg-white hover:bg-white/50"
            phx-click={JS.dispatch("click", to: "#uploader-file-form .image-input")}
          >
            <.icon id="image" class="w-4 h-4 fill-grayscale" />
            <span class="ml-2">Image</span>
          </a>
          <a
            class="flex justify-center items-center h-11 w-[30%] pr-2 cursor-pointer rounded-md bg-white"
            phx-click={JS.dispatch("click", to: "#uploader-file-form .audio-file-input")}
          >
            <.icon id="audio" class="w-4 h-4 fill-grayscale" />
            <span class="ml-2">Audio</span>
          </a>
        </div>

        <input
          accept="image/*, video/*"
          class="image-input hidden p-1 flex flex-col items-center text-sm text-black/50 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-purple file:text-purple50 file:cursor-pointer"
          data-ref={@config.ref}
          id={"#{@config.ref}-android"}
          name="media_file"
          phx-hook="MediaFileInput"
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
