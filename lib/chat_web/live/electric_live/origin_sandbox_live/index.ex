defmodule ChatWeb.ElectricLive.OriginSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing origin Electric API operations."

  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.OriginSandboxLive.ApiClient

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, owner: nil, origin: nil, request_log: [], error_message: nil)}
  end

  @impl true
  def handle_event("create_owner", %{"name" => name}, socket) do
    base_url = ChatWeb.Endpoint.url()

    case ApiClient.create_user(name, base_url) do
      {:ok, %{user: user, log_entries: logs}} ->
        {:noreply, socket |> assign(owner: user) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("create_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = ChatWeb.Endpoint.url()
    owner = socket.assigns.owner

    case ApiClient.create_origin(owner, name, mode, base_url) do
      {:ok, %{origin: origin, log_entries: logs}} ->
        {:noreply, socket |> assign(origin: origin) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("update_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = ChatWeb.Endpoint.url()
    %{origin: origin} = socket.assigns

    case ApiClient.update_origin(origin, name, mode, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        {:noreply, socket |> assign(origin: updated) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  defp append_logs(socket, logs) do
    update(socket, :request_log, &(logs ++ &1))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Origin Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">Test origin creation and management via Electric API</p>

        <%= if @error_message do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
            <span>{@error_message}</span>
            <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
          </div>
        <% end %>

        <div class="space-y-6">
          {render_owner_section(assigns)}
          <%= if @owner do %>
            {render_origin_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_owner_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Owner Identity</h2>
      <%= if @owner do %>
        <div class="text-sm space-y-1">
          <p><span class="font-medium">Name:</span> {@owner.name}</p>
          <p class="font-mono text-xs text-gray-500 truncate">
            <span class="font-medium font-sans">Hash:</span> {@owner.user_hash}
          </p>
        </div>
      <% else %>
        <form phx-submit="create_owner" class="flex gap-3">
          <input
            type="text"
            name="name"
            value="Origin Owner"
            required
            class="flex-1 px-3 py-2 border rounded-lg"
          />
          <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700">
            Create Owner
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_origin_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 2: Origin</h2>
      <%= if @origin do %>
        <div class="text-sm space-y-1 mb-4">
          <p><span class="font-medium">Name (encrypted):</span> {@origin.name}</p>
          <p class="font-mono text-xs text-gray-500 truncate">
            <span class="font-medium font-sans">Origin hash:</span> {@origin.origin_hash}
          </p>
          <p><span class="font-medium">Moderation:</span> {@origin.moderation_mode}</p>
          <p><span class="font-medium">Timestamp:</span> {@origin.owner_timestamp}</p>
        </div>
        <form phx-submit="update_origin" class="flex gap-3 items-end">
          <div class="flex-1">
            <label class="block text-xs font-medium text-gray-700 mb-1">New name</label>
            <input
              type="text"
              name="name"
              value={@origin.name}
              required
              class="w-full px-3 py-2 border rounded-lg text-sm"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Moderation</label>
            <select name="moderation" class="px-3 py-2 border rounded-lg text-sm">
              <option value="none" selected={@origin.moderation_mode == "none"}>none</option>
              <option value="post" selected={@origin.moderation_mode == "post"}>post</option>
              <option value="pre" selected={@origin.moderation_mode == "pre"}>pre</option>
            </select>
          </div>
          <button
            type="submit"
            class="bg-yellow-600 text-white px-4 py-2 rounded-lg hover:bg-yellow-700 text-sm"
          >
            Update
          </button>
        </form>
      <% else %>
        <form phx-submit="create_origin" class="flex gap-3 items-end">
          <div class="flex-1">
            <label class="block text-xs font-medium text-gray-700 mb-1">Origin name</label>
            <input
              type="text"
              name="name"
              value="Test Coffee Shop"
              required
              class="w-full px-3 py-2 border rounded-lg text-sm"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Moderation</label>
            <select name="moderation" class="px-3 py-2 border rounded-lg text-sm">
              <option value="none">none</option>
              <option value="post">post</option>
              <option value="pre">pre</option>
            </select>
          </div>
          <button
            type="submit"
            class="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 text-sm"
          >
            Create Origin
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_log_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Request Log</h2>
      <%= if @request_log == [] do %>
        <p class="text-sm text-gray-500">No requests yet</p>
      <% else %>
        <div class="space-y-3">
          <div
            :for={entry <- @request_log}
            class={"text-xs font-mono p-3 rounded #{if entry.response_status in 200..299, do: "bg-green-50", else: "bg-red-50"}"}
          >
            <p class="font-semibold">{entry.method} {entry.url} -> {entry.response_status}</p>
            <details class="mt-1">
              <summary class="cursor-pointer text-gray-600">Response body</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.response_body}</pre>
            </details>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
