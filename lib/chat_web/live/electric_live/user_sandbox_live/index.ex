defmodule ChatWeb.ElectricLive.UserSandboxLive.Index do
  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.UserSandboxLive.Components
  alias ChatWeb.ElectricLive.UserSandboxLive.Modals
  alias ChatWeb.ElectricLive.UserSandboxLive.Router

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        user: nil,
        storage_items: [],
        show_storage_form: false,
        editing_storage_uuid: nil,
        viewing_storage_uuid: nil,
        request_log: [],
        show_docs: true,
        expanded_docs: MapSet.new(["user_card"]),
        operation_in_progress: false,
        error_message: nil
      )
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-gray-50" id="user-sandbox" phx-hook="DownloadFile">
      <.header />
      <div class="flex-1 flex overflow-hidden">
        {Components.docs_sidebar(assigns)}
        <main class="flex-1 overflow-y-auto p-6">
          <%= if @error_message do %>
            <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded">
              <div class="flex justify-between items-start">
                <div>
                  <strong class="font-semibold">Error:</strong>
                  <span class="block mt-1">{@error_message}</span>
                </div>
                <button phx-click="clear_error" class="text-red-600 hover:text-red-800">✕</button>
              </div>
            </div>
          <% end %>
          <%= if @user do %>
            {Components.user_loaded(assigns)}
          <% else %>
            {render_initial_state(assigns)}
          <% end %>
        </main>
        {Components.request_log(assigns)}
      </div>
      <%= if @show_storage_form do %>
        {Modals.storage_form(assigns)}
      <% end %>
      <%= if @viewing_storage_uuid do %>
        {Modals.storage_details(assigns)}
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event(event, params, socket) do
    Router.handle_event(event, params, socket)
  end

  defp header(assigns) do
    ~H"""
    <div class="bg-white border-b px-6 py-4">
      <h1 class="text-2xl font-bold text-gray-900">Electric API Sandbox</h1>
      <p class="text-sm text-gray-600 mt-1">
        Interactive test client for user_card and user_storage Electric API operations
      </p>
    </div>
    """
  end

  defp render_initial_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="text-center">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">No user loaded</h2>
        <p class="text-gray-600 mb-6">Create a test user to begin testing the Electric API</p>
        <form phx-submit="create_user" class="space-y-4">
          <input
            type="text"
            name="name"
            placeholder="Enter user name"
            value="Test User"
            class="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            required
            disabled={@operation_in_progress}
          />
          <button
            type="submit"
            disabled={@operation_in_progress}
            class="block w-full bg-blue-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition"
          >
            {if @operation_in_progress, do: "Creating...", else: "Create Test User"}
          </button>
        </form>

        <div class="mt-6 pt-6 border-t border-gray-200">
          <p class="text-gray-500 text-sm mb-4">or import existing identity</p>
          <form phx-submit="import_keys" phx-change="validate_key_file" class="space-y-3">
            <.live_file_input upload={@uploads.key_file} class="text-sm" />
            <button
              type="submit"
              disabled={@uploads.key_file.entries == []}
              class="block w-full bg-green-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition"
            >
              Import Keys
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
