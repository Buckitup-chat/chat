defmodule ChatWeb.ElectricLive.OriginSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing origin owner operations via Electric API."

  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.OriginSandboxLive.ApiClient

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(owner: nil, origin: nil, request_log: [], error_message: nil)
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} ->
        {:noreply, assign(socket, owner: user_data, error_message: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Import failed: #{reason}")}
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

  def handle_event("delete_origin", _params, socket) do
    base_url = ChatWeb.Endpoint.url()
    %{origin: origin} = socket.assigns

    case ApiClient.delete_origin(origin, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        {:noreply, socket |> assign(origin: updated) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("export_origin_identity", _params, socket) do
    origin = socket.assigns.origin
    short_hash = String.slice(origin.origin_hash, 2, 8)
    filename = "origin_identity_#{short_hash}.json"

    data =
      Jason.encode!(
        %{
          type: "buckitup_origin_identity",
          version: 1,
          origin_hash: origin.origin_hash,
          name: origin.name,
          sign_skey: Base.encode64(origin.origin_sign_skey, padding: false),
          crypt_skey: Base.encode64(origin[:origin_crypt_skey] || "", padding: false)
        },
        pretty: true
      )

    {:noreply, push_event(socket, "download_file", %{data: data, filename: filename})}
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
    <div class="min-h-screen bg-gray-50 py-8" id="origin-owner-sandbox" phx-hook="DownloadFile">
      <div class="max-w-4xl mx-auto px-4">
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Origin Owner Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">
          Test origin creation, management, and ownership operations via Electric API
        </p>

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
          <%= if @origin do %>
            {render_operations_section(assigns)}
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
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Owner</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <%= if @owner do %>
        <div class="text-sm">
          <span class="font-medium text-green-700">Identity loaded:</span>
          <span class="font-mono text-xs text-gray-600">{@owner.user_hash}</span>
          <span class="text-gray-500">({@owner.name})</span>
        </div>
      <% else %>
        <form phx-change="validate_key_file" phx-submit="import_keys" class="flex items-center gap-4">
          <.live_file_input upload={@uploads.key_file} class="text-sm" />
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm"
          >
            Import Keys
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
          <p><span class="font-medium">Name:</span> {@origin.name}</p>
          <p class="font-mono text-xs text-gray-500 truncate">
            <span class="font-medium font-sans">Origin hash:</span> {@origin.origin_hash}
          </p>
          <p><span class="font-medium">Owner:</span> {@origin.owner_hash}</p>
          <p><span class="font-medium">Moderation:</span> {@origin.moderation_mode}</p>
          <p><span class="font-medium">Deleted:</span> {to_string(@origin.deleted_flag)}</p>
          <p><span class="font-medium">Timestamp:</span> {@origin.owner_timestamp}</p>
        </div>
        {render_identity_export(assigns)}
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

  defp render_identity_export(assigns) do
    ~H"""
    <button
      phx-click="export_origin_identity"
      class="mt-3 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 text-sm"
    >
      Export Origin Identity
    </button>
    """
  end

  defp render_operations_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 3: Owner Operations</h2>

      <div class="space-y-4">
        <div class="border-b pb-4">
          <h3 class="text-sm font-semibold text-gray-700 mb-2">Update</h3>
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
        </div>

        <div>
          <h3 class="text-sm font-semibold text-gray-700 mb-2">Delete</h3>
          <button
            phx-click="delete_origin"
            disabled={@origin.deleted_flag}
            class={"px-4 py-2 rounded-lg text-sm text-white #{if @origin.deleted_flag, do: "bg-gray-400 cursor-not-allowed", else: "bg-red-600 hover:bg-red-700"}"}
          >
            {if @origin.deleted_flag, do: "Deleted", else: "Delete Origin"}
          </button>
        </div>
      </div>
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
              <summary class="cursor-pointer text-gray-600">Request headers</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.request_headers)}</pre>
            </details>
            <%= if entry.request_body != "" do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Request body</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.request_body}</pre>
              </details>
            <% end %>
            <details class="mt-1">
              <summary class="cursor-pointer text-gray-600">Response headers</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.response_headers)}</pre>
            </details>
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

  defp format_headers(headers) when is_list(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp format_headers(_), do: ""
end
