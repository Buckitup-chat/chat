defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing review author operations via Electric API."

  use ChatWeb, :live_view

  alias Chat.Data.Schemas.Origin
  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient
  alias Electric.Client.Message

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        author: nil,
        origin_hash: nil,
        review: nil,
        request_log: [],
        error_message: nil,
        origins: [],
        selected_rating: 0
      )
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    if connected?(socket), do: fetch_origins_async()

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
          Test review submission, moderation pipeline, and review list via Electric API
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
          <span class="font-mono text-xs text-gray-600">
            {Shortcode.short_code(@author.user_hash)}
          </span>
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
            <span class="font-mono text-xs">{Shortcode.short_code(@review.review_hash)}</span>
          </p>
          <p>
            <span class="font-medium">Origin:</span>
            <span class="font-mono text-xs">{Shortcode.short_code(@review.origin_hash)}</span>
          </p>
          <p>
            <span class="font-medium">Rating:</span>
            <span class="text-yellow-400">{String.duplicate("★", @review.rating)}</span>
            <span class="text-gray-300">{String.duplicate("★", 5 - @review.rating)}</span>
          </p>
          <%= if @review.text != "" do %>
            <p><span class="font-medium">Text:</span> {@review.text}</p>
          <% end %>
          <p><span class="font-medium">Timestamp:</span> {@review.owner_timestamp}</p>
        </div>
      <% else %>
        <form phx-submit="submit_review" phx-change="form_changed" class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Origin</label>
            <select name="origin_hash" required class="w-full px-3 py-2 border rounded-lg text-sm">
              <option value="">Select an origin...</option>
              <option
                :for={origin <- @origins}
                value={origin.origin_hash}
                selected={origin.origin_hash == @origin_hash}
              >
                {origin.name}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Rating</label>
            <div class="flex gap-1">
              <button
                :for={n <- 1..5}
                type="button"
                phx-click="set_rating"
                phx-value-rating={n}
                class="text-2xl focus:outline-none"
              >
                <span class={if n <= @selected_rating, do: "text-yellow-400", else: "text-gray-300"}>
                  ★
                </span>
              </button>
            </div>
            <input type="hidden" name="rating" value={@selected_rating} />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">
              Review text <span class="text-gray-400">(optional)</span>
            </label>
            <textarea
              name="content"
              rows="3"
              class="w-full px-3 py-2 border rounded-lg text-sm"
              placeholder="Write your review..."
            ></textarea>
          </div>
          <button
            type="submit"
            disabled={@selected_rating == 0}
            class={"bg-green-600 text-white px-4 py-2 rounded-lg text-sm #{if @selected_rating == 0, do: "opacity-50 cursor-not-allowed", else: "hover:bg-green-700"}"}
          >
            Submit Review
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_review_list_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6 opacity-60">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">
        Step 3: Add to Review List
      </h2>
      <p class="text-sm text-gray-500 italic">Not implemented yet</p>
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
            class={"text-xs font-mono p-3 rounded #{log_entry_class(entry)}"}
          >
            <p class="font-semibold">{log_entry_label(entry)}</p>
            <%= if entry[:request_headers] do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Request headers</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.request_headers)}</pre>
              </details>
            <% end %>
            <%= if entry[:request_body] && entry.request_body != "" do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Request body</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.request_body}</pre>
              </details>
            <% end %>
            <%= if entry[:response_headers] do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Response headers</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{format_headers(entry.response_headers)}</pre>
              </details>
            <% end %>
            <%= if entry[:response_body] do %>
              <details class="mt-1">
                <summary class="cursor-pointer text-gray-600">Response body</summary>
                <pre class="mt-1 whitespace-pre-wrap text-xs overflow-x-auto">{entry.response_body}</pre>
              </details>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Info ---

  @impl true
  def handle_info({:origins_loaded, origins}, socket) do
    {:noreply, assign(socket, origins: origins)}
  end

  # --- Events ---

  @impl true
  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} ->
        author = Map.put(user_data, :review_list_password, :crypto.strong_rand_bytes(32))
        {:noreply, assign(socket, author: author, error_message: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Import failed: #{reason}")}
    end
  end

  def handle_event("form_changed", %{"origin_hash" => origin_hash}, socket) do
    {:noreply, assign(socket, origin_hash: origin_hash)}
  end

  def handle_event("set_rating", %{"rating" => rating}, socket) do
    {:noreply, assign(socket, selected_rating: String.to_integer(rating))}
  end

  def handle_event(
        "submit_review",
        %{"origin_hash" => origin_hash, "rating" => raw_rating} = params,
        socket
      ) do
    text = Map.get(params, "content", "")
    rating = String.to_integer(raw_rating)
    content = Jason.encode!(%{rating: rating, text: text})

    case ApiClient.submit_review(socket.assigns.author, origin_hash, content, ChatWeb.Endpoint.url()) do
      {:ok, %{review: review, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(
           review: Map.merge(review, %{rating: rating, text: text}),
           origin_hash: origin_hash
         )
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, error_message: nil)}
  end

  # --- Private ---

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  defp log_entry_label(%{method: method, url: url, response_status: status}),
    do: "#{method} #{url} -> #{status}"

  defp log_entry_label(%{label: label}), do: label

  defp log_entry_class(%{response_status: status}) when status in 200..299, do: "bg-green-50"
  defp log_entry_class(%{response_status: _}), do: "bg-red-50"
  defp log_entry_class(%{status: :ok}), do: "bg-green-50"
  defp log_entry_class(%{status: :error}), do: "bg-red-50"
  defp log_entry_class(_), do: "bg-gray-50"

  defp format_headers(headers) do
    Enum.map_join(headers, "\n", fn {k, v} -> "#{k}: #{v}" end)
  end

  defp fetch_origins_async do
    pid = self()
    endpoint_url = ChatWeb.Endpoint.url() <> "/electric/v1/shapes"
    client = Electric.Client.new!(endpoint: endpoint_url)

    shape =
      Electric.Client.ShapeDefinition.new!("origins",
        parser: {Electric.Client.EctoAdapter, Origin}
      )

    Task.start_link(fn ->
      origins =
        client
        |> Electric.Client.stream(shape, live: false, replica: :full)
        |> Enum.reduce_while([], fn
          %Message.ChangeMessage{headers: %{operation: :insert}, value: value}, acc ->
            {:cont, [value | acc]}

          %Message.ControlMessage{control: :up_to_date}, acc ->
            {:halt, acc}

          _, acc ->
            {:cont, acc}
        end)
        |> Enum.reject(& &1.deleted_flag)
        |> Enum.sort_by(& &1.name)

      send(pid, {:origins_loaded, origins})
    end)
  end
end
