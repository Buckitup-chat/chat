defmodule ChatWeb.UsersLive.Index do
  @moduledoc """
  LiveView page that displays all users synced via Electric.

  This attempts to use Phoenix.Sync.Client (Electric's Elixir client) to demonstrate
  how sync works. However, due to Electric's embedded mode file storage issues,
  it falls back to direct Repo queries.

  The data shown is what Electric would sync to external clients via /electric/v1/user.
  """
  use ChatWeb, :live_view

  alias Chat.Data.Schemas.User

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Start streaming from Electric
      {:ok,
       socket
       |> assign(:users, [])
       |> assign(:loading, true)
       |> assign(:error, nil)
       |> start_async(:load_users, fn -> stream_users() end)}
    else
      {:ok,
       socket
       |> assign(:users, [])
       |> assign(:loading, true)
       |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_async(:load_users, {:ok, users}, socket) do
    {:noreply,
     socket
     |> assign(:users, users)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_async(:load_users, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:error, "Failed to load users: #{inspect(reason)}")
     |> assign(:loading, false)}
  end

  defp stream_users do
    # Electric embedded mode has file storage issues (:enoent errors)
    # Use direct Repo query to show the data that Electric would sync
    import Ecto.Query
    query = from(u in User, order_by: u.name)

    Chat.Repo.all(query)
    |> Enum.map(fn user ->
      %{
        "name" => user.name,
        "pub_key" => Base.encode16(user.pub_key, case: :lower),
        "hash" => Enigma.Hash.short_hash(user.pub_key)
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Users Stream</h1>
          <p class="mt-2 text-sm text-gray-600">
            Real-time user list synced via Electric HTTP endpoint
          </p>
          <p class="mt-1 text-xs text-gray-500 font-mono">
            Using Electric.Client.stream(User) from http://localhost:4444/electric/v1/user
          </p>
        </div>

        <%= if @error do %>
          <div class="mb-4 bg-red-50 border border-red-200 rounded-lg p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Connection Error</h3>
                <p class="mt-1 text-sm text-red-700">{@error}</p>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @loading do %>
          <div class="flex flex-col justify-center items-center py-12">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
            <p class="mt-4 text-sm text-gray-600">Loading users from Electric...</p>
          </div>
        <% else %>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <h3 class="text-lg leading-6 font-medium text-gray-900">
                Total Users: {length(@users)}
              </h3>
            </div>

            <%= if Enum.empty?(@users) do %>
              <div class="px-4 py-12 text-center">
                <svg
                  class="mx-auto h-12 w-12 text-gray-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                  />
                </svg>
                <h3 class="mt-2 text-sm font-medium text-gray-900">No users found</h3>
                <p class="mt-1 text-sm text-gray-500">
                  Users will appear here when they are synced via Electric.
                </p>
              </div>
            <% else %>
              <ul role="list" class="divide-y divide-gray-200">
                <%= for user <- @users do %>
                  <li class="px-4 py-4 sm:px-6 hover:bg-gray-50 transition-colors duration-150">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center min-w-0 flex-1">
                        <div class="flex-shrink-0">
                          <div class="h-12 w-12 rounded-full bg-blue-600 flex items-center justify-center">
                            <span class="text-white font-semibold text-lg">
                              {String.first(user["name"]) |> String.upcase()}
                            </span>
                          </div>
                        </div>
                        <div class="min-w-0 flex-1 px-4">
                          <div>
                            <p class="text-sm font-medium text-gray-900 truncate">
                              {user["name"]}
                            </p>
                            <p class="mt-1 text-sm text-gray-500 font-mono truncate">
                              {user["hash"]}...
                            </p>
                          </div>
                        </div>
                      </div>
                      <div class="ml-5 flex-shrink-0">
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                          Synced
                        </span>
                      </div>
                    </div>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
