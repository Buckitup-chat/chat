defmodule ChatWeb.ElectricLive.DialogSandboxLive.ContentComponents do
  @moduledoc false

  use Phoenix.Component

  alias ChatWeb.ElectricLive.DialogSandboxLive.Content

  attr :content, :any, required: true
  attr :message_id, :string, required: true
  attr :deleted, :boolean, default: false

  def render_content(%{deleted: true} = assigns) do
    ~H"""
    <div class="text-sm italic text-gray-400">[deleted]</div>
    """
  end

  def render_content(%{content: {:text, text}} = assigns) do
    assigns = assign(assigns, :text, text)

    ~H"""
    <div class="text-sm">{@text}</div>
    """
  end

  def render_content(%{content: {:inline_image, meta}} = assigns) do
    assigns = assign(assigns, :meta, meta)

    ~H"""
    <div class="space-y-1">
      <img
        src={"data:#{@meta.mime};base64,#{@meta.data_b64}"}
        class="max-w-full max-h-64 rounded"
        style={"aspect-ratio: #{@meta.w_aspect}/#{@meta.h_aspect}"}
      />
      <div class="text-xs text-gray-500">
        {@meta.name} · {Content.format_size(@meta.size)} · {@meta.mime}
      </div>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  def render_content(%{content: {:inline_file, meta}} = assigns) do
    assigns = assign(assigns, :meta, meta)

    ~H"""
    <div class="border rounded p-2 bg-gray-50 space-y-1">
      <div class="flex items-center gap-2 text-sm">
        <span class="text-lg">📎</span>
        <div>
          <div class="font-medium">{@meta.name}</div>
          <div class="text-xs text-gray-500">
            {Content.format_size(@meta.size)} · {@meta.mime}
          </div>
        </div>
      </div>
      <a
        href={"data:#{@meta.mime};base64,#{@meta.data_b64}"}
        download={@meta.name}
        class="inline-block text-xs text-blue-600 hover:underline"
      >
        Download
      </a>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  def render_content(%{content: {:file, meta}} = assigns) do
    assigns = assign(assigns, :meta, meta)

    ~H"""
    <div class="border rounded p-2 bg-gray-50 space-y-1">
      <div class="flex items-center gap-2 text-sm">
        <span class="text-lg">📁</span>
        <div>
          <div class="font-medium">{@meta.name}</div>
          <div class="text-xs text-gray-500">
            {Content.format_size(@meta.size)} · {@meta.mime}
          </div>
        </div>
      </div>
      <div class="text-xs font-mono text-gray-400 truncate" title={@meta.file_id}>
        {@meta.file_id}
      </div>
      <div class="text-xs text-amber-600">Out-of-band file — use File Sandbox to download</div>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  def render_content(%{content: {:image, meta}} = assigns) do
    assigns = assign(assigns, :meta, meta)

    ~H"""
    <div class="border rounded p-2 bg-gray-50 space-y-1">
      <div
        class="bg-gray-200 rounded flex items-center justify-center text-gray-400 text-2xl"
        style={"aspect-ratio: #{@meta.w_aspect}/#{@meta.h_aspect}; max-height: 10rem;"}
      >
        🖼
      </div>
      <div class="text-sm font-medium">{@meta.name}</div>
      <div class="text-xs text-gray-500">
        {Content.format_size(@meta.size)} · {@meta.mime} · {@meta.w_aspect}:{@meta.h_aspect}
      </div>
      <div class="text-xs font-mono text-gray-400 truncate" title={@meta.file_id}>
        {@meta.file_id}
      </div>
      <div class="text-xs text-amber-600">Out-of-band image — use File Sandbox to download</div>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  def render_content(%{content: {:video, meta}} = assigns) do
    assigns = assign(assigns, :meta, meta)

    ~H"""
    <div class="border rounded p-2 bg-gray-50 space-y-1">
      <div
        class="bg-gray-200 rounded flex items-center justify-center text-gray-400 text-2xl"
        style={"aspect-ratio: #{@meta.w_aspect}/#{@meta.h_aspect}; max-height: 10rem;"}
      >
        ▶
      </div>
      <div class="text-sm font-medium">{@meta.name}</div>
      <div class="text-xs text-gray-500">
        {Content.format_size(@meta.size)} · {@meta.mime} · {@meta.w_aspect}:{@meta.h_aspect}
      </div>
      <div class="text-xs font-mono text-gray-400 truncate" title={@meta.file_id}>
        {@meta.file_id}
      </div>
      <div class="text-xs text-amber-600">Out-of-band video — use File Sandbox to download</div>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  def render_content(%{content: {:composed, elements}} = assigns) do
    assigns = assign(assigns, :elements, elements)

    ~H"""
    <div class="space-y-2">
      <%= for {element, idx} <- Enum.with_index(@elements) do %>
        <.render_content content={element} message_id={"#{@message_id}-c#{idx}"} deleted={false} />
      <% end %>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  def render_content(%{content: {:unknown, json}} = assigns) do
    assigns = assign(assigns, :json, json)

    ~H"""
    <div class="space-y-1">
      <div class="text-xs text-amber-600 font-medium">Unknown content type</div>
      <pre class="text-xs bg-gray-100 p-2 rounded overflow-x-auto max-h-32 overflow-y-auto">{@json}</pre>
      <.copy_json_button content={@content} message_id={@message_id} />
    </div>
    """
  end

  defp copy_json_button(assigns) do
    assigns = assign(assigns, :json, Content.to_json(assigns.content))

    ~H"""
    <div class="mt-1">
      <input type="hidden" id={"content-json-#{@message_id}"} value={@json} />
      <button
        phx-click={Phoenix.LiveView.JS.dispatch("phx:copy", to: "#content-json-#{@message_id}")}
        class="text-[10px] px-1.5 py-0.5 bg-gray-100 hover:bg-gray-200 rounded text-gray-600"
      >
        Copy JSON
      </button>
    </div>
    """
  end
end
