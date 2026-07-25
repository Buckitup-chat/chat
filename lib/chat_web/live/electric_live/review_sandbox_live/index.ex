defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing review author operations via Electric API."

  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.ReviewSandboxLive.Render

  alias Chat.Data.Schemas.Origin
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Verification
  alias Electric.Client.Message

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      author: nil,
      origin_hash: nil,
      moderation_mode: nil,
      review: nil,
      rights_submitted: false,
      right_candidates: nil,
      shared_secrets: %{},
      verification: nil,
      rights_signed: false,
      request_log: [],
      error_message: nil,
      origins: [],
      selected_rating: 0
    )
    |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)
    |> tap(fn s -> if connected?(s), do: fetch_origins_async(base_url(s)) end)
    |> then(&{:ok, &1})
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
            {render_rights_section(assigns)}
          <% end %>
          <%= if @rights_submitted and @moderation_mode not in [:none, nil] do %>
            {render_sign_section(assigns)}
          <% end %>
          <%= if rights_complete?(assigns) do %>
            {render_review_list_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
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
    mode = find_moderation_mode(socket.assigns.origins, origin_hash)
    {:noreply, assign(socket, origin_hash: origin_hash, moderation_mode: mode)}
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
    {placeholder, review_text} = review_content_parts(text)
    content = Jason.encode!([rating, placeholder, review_text])

    case ApiClient.submit_review(
           socket.assigns.author,
           origin_hash,
           content,
           ChatWeb.Endpoint.url()
         ) do
      {:ok, %{review: review, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(
           review: Map.merge(review, %{rating: rating, text: text, content_json: content}),
           origin_hash: origin_hash
         )
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("submit_rights", _params, socket) do
    %{author: author, review: review} = socket.assigns

    case ApiClient.submit_password_candidates(author, review, ChatWeb.Endpoint.url()) do
      {:ok, %{candidates: candidates, shared_secrets: shared_secrets, log_entries: logs}} ->
        {:noreply,
         socket
         |> assign(
           rights_submitted: true,
           right_candidates: candidates,
           shared_secrets: shared_secrets
         )
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("verify_wrapping", _params, socket) do
    %{
      author: author,
      right_candidates: candidates,
      shared_secrets: shared_secrets,
      review: review
    } = socket.assigns

    verification = Verification.verify_candidates(candidates, shared_secrets, review, author)
    {:noreply, assign(socket, verification: verification)}
  end

  def handle_event("sign_rights", _params, socket) do
    %{
      author: author,
      right_candidates: candidates,
      shared_secrets: shared_secrets,
      review: review
    } =
      socket.assigns

    case ApiClient.sign_right_candidates(
           author,
           candidates,
           shared_secrets,
           review,
           ChatWeb.Endpoint.url()
         ) do
      {:ok, %{log_entries: logs}} ->
        {:noreply, socket |> assign(rights_signed: true) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, error_message: nil)}
  end

  # --- Private ---

  defp review_content_parts("") do
    length = Enum.random(20..200)
    placeholder = length |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {placeholder, ""}
  end

  defp review_content_parts(text), do: {"", text}

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  defp find_moderation_mode(origins, origin_hash) do
    case Enum.find(origins, &(&1.origin_hash == origin_hash)) do
      %{moderation_mode: mode} -> mode
      _ -> nil
    end
  end

  defp rights_complete?(assigns) do
    cond do
      not assigns.rights_submitted -> false
      assigns.moderation_mode == :none -> true
      assigns.rights_signed -> true
      true -> false
    end
  end

  defp base_url(socket) do
    uri = socket.host_uri
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end

  defp fetch_origins_async(endpoint_base) do
    pid = self()
    client = Electric.Client.new!(endpoint: endpoint_base <> "/electric/v1/shapes")

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
