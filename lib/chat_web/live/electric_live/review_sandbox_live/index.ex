defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing review author operations via Electric API."

  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        author: nil,
        origin_hash: nil,
        review: nil,
        review_password_sign_hash: nil,
        request_log: [],
        error_message: nil
      )
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Review Author Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">
          Test review submission, password publication, and review list via Electric API
        </p>

        <%= if @error_message do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
            <span>{@error_message}</span>
            <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
          </div>
        <% end %>

        <div class="space-y-6">
          {render_author_section(assigns)}
          <%= if @author do %>
            {render_review_section(assigns)}
          <% end %>
          <%= if @review do %>
            {render_password_section(assigns)}
          <% end %>
          <%= if @review_password_sign_hash do %>
            {render_review_list_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_author_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Author Identity</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <%= if @author do %>
        <div class="text-sm">
          <span class="font-medium text-green-700">Identity loaded:</span>
          <span class="font-mono text-xs text-gray-600">{@author.user_hash}</span>
          <span class="text-gray-500">({@author.name})</span>
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

  defp render_review_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 2: Submit Review</h2>
      <%= if @review do %>
        <div class="text-sm space-y-1">
          <p>
            <span class="font-medium">Review hash:</span>
            <span class="font-mono text-xs">{@review.review_hash}</span>
          </p>
          <p>
            <span class="font-medium">Origin:</span>
            <span class="font-mono text-xs">{@review.origin_hash}</span>
          </p>
          <p><span class="font-medium">Content:</span> {@review.content}</p>
          <p><span class="font-medium">Timestamp:</span> {@review.owner_timestamp}</p>
        </div>
      <% else %>
        <form phx-submit="submit_review" class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Origin hash</label>
            <input
              type="text"
              name="origin_hash"
              required
              placeholder="u_..."
              class="w-full px-3 py-2 border rounded-lg text-sm font-mono"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Review content</label>
            <textarea
              name="content"
              required
              rows="3"
              class="w-full px-3 py-2 border rounded-lg text-sm"
              placeholder="Write your review..."
            ></textarea>
          </div>
          <button
            type="submit"
            class="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 text-sm"
          >
            Submit Review
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_password_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 3: Publish Password</h2>
      <p class="text-sm text-gray-600 mb-3">
        Submit the review password to make the review publicly decryptable.
      </p>
      <%= if @review_password_sign_hash do %>
        <div class="text-sm text-green-700">
          <span class="font-medium">Password published.</span>
          <span class="font-mono text-xs">{@review_password_sign_hash}</span>
        </div>
      <% else %>
        <button
          phx-click="submit_password"
          class="bg-yellow-600 text-white px-4 py-2 rounded-lg hover:bg-yellow-700 text-sm"
        >
          Submit Password Candidate
        </button>
      <% end %>
    </div>
    """
  end

  defp render_review_list_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 4: Add to Review List</h2>
      <p class="text-sm text-gray-600 mb-3">
        Add this review to your review_list so contacts can access it.
      </p>
      <button
        phx-click="submit_review_list"
        class="bg-purple-600 text-white px-4 py-2 rounded-lg hover:bg-purple-700 text-sm"
      >
        Submit Review List Entry
      </button>
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
              <summary class="cursor-pointer text-gray-600">Details</summary>
              <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.response_body}</pre>
            </details>
          </div>
        </div>
      <% end %>
    </div>
    """
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
        review_list_password = :crypto.strong_rand_bytes(32)
        author = Map.put(user_data, :review_list_password, review_list_password)
        {:noreply, assign(socket, author: author, error_message: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Import failed: #{reason}")}
    end
  end

  def handle_event("submit_review", %{"origin_hash" => origin_hash, "content" => content}, socket) do
    base_url = ChatWeb.Endpoint.url()

    case ApiClient.submit_review(socket.assigns.author, origin_hash, content, base_url) do
      {:ok, %{review: review, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(review: review, origin_hash: origin_hash)
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("submit_password", _params, socket) do
    base_url = ChatWeb.Endpoint.url()
    %{author: author, review: review, origin_hash: origin_hash} = socket.assigns

    case ApiClient.submit_password_candidate(author, review, origin_hash, base_url) do
      {:ok, %{sign_hash: sh, log_entries: logs}} ->
        {:noreply, socket |> assign(review_password_sign_hash: sh) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("submit_review_list", _params, socket) do
    base_url = ChatWeb.Endpoint.url()
    %{author: author, review: review, review_password_sign_hash: psh} = socket.assigns

    case ApiClient.submit_review_list_entry(author, review, psh, base_url) do
      {:ok, %{log_entries: logs}} ->
        {:noreply, append_logs(socket, logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  # --- Private ---

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))
end
