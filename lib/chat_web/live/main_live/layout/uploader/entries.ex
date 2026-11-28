defmodule ChatWeb.MainLive.Layout.Uploader.Entries do
  @moduledoc """
  Upload entries list of `ChatWeb.MainLive.Layout.Uploader`: one row per upload with
  progress and pause / resume / cancel controls, plus hidden upload errors.
  """
  use ChatWeb, :component

  alias Chat.Upload.UploadMetadata
  alias Phoenix.LiveView.{JS, UploadConfig, UploadEntry, Utils}

  attr :config, UploadConfig, required: true, doc: "upload config"
  attr :mobile?, :boolean, default: false, doc: "whether it's a mobile file uploader"
  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :type, :atom, required: true, doc: ":dialog or :room"
  attr :uploads, :map, required: true, doc: "uploads metadata"
  attr :uploads_order, :list, required: true, doc: "uploads order"

  def entries(%{uploads: uploads} = assigns) when map_size(uploads) > 0 do
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
      <.entries_errors config={@config} />
    </div>
    """
  end

  def entries(assigns) do
    ~H""
  end

  attr :config, UploadConfig, required: true, doc: "upload config"

  defp entries_errors(assigns) do
    ~H"""
    <div id={"uploadErrors-" <> Utils.random_id()} class="hidden" phx-update="replace">
      <%= for entry <- @config.entries do %>
        <%= for err <- upload_errors(@config, entry) do %>
          <p id={"err-" <> Utils.random_id()} phx-mounted={pause_upload(entry.uuid)}>
            {err}
          </p>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :entry, UploadEntry, doc: "upload entry"
  attr :mobile?, :boolean, required: true
  attr :metadata, UploadMetadata, doc: "upload metadata"
  attr :pub_key, :string, required: true, doc: "peer or room pub key"
  attr :type, :atom, required: true, doc: ":dialog or :room"

  defp entry(%{entry: nil, metadata: nil} = assigns) do
    ~H""
  end

  defp entry(assigns) do
    assigns = Map.put(assigns, :in_current_room, current_room?(assigns))

    ~H"""
    <div
      class={
        classes("flex mb-2 border-purple relative w-full z-0", %{
          "bg-white" => @in_current_room,
          "bg-pink-100" => !@in_current_room
        })
      }
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
            <span class="truncate">{@entry.client_name}</span>
          </div>

          <div class="flex text-xs ml-auto text-black/50">{@entry.progress}%</div>
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

  defp current_room?(%{pub_key: nil}), do: false

  defp current_room?(%{
         metadata: %{destination: %{type: dst_type, pub_key: pub_key}},
         type: dst_type,
         pub_key: bin_pub_key
       }),
       do: pub_key == bin_pub_key |> Base.encode16(case: :lower)

  defp current_room?(_), do: false

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
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
