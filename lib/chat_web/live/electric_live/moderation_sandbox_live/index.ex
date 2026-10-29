defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Index do
  @moduledoc """
  Origin Console — the single sandbox for moderation, settings, bots, and write tokens.

  Authenticates as the origin identity (not the owner), reads the origin's
  reviews and right envelopes via Electric shapes, KEM-decrypts the rights, and
  publishes or revokes public visibility by ingesting the author's pre-signed
  `review_public_passwords` row.
  """

  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.ModerationSandboxLive.Render
  import ChatWeb.ElectricLive.RequestLog, only: [render_log_section: 1]

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ModerationSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Identity
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Manage
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Queue
  alias ChatWeb.ElectricLive.ModerationSandboxLive.ReviewBot
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Settings
  alias ChatWeb.ElectricLive.ModerationSandboxLive.WriteToken

  @manage_events Manage.events()

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      identity: nil,
      origin: nil,
      origin_card: nil,
      verification: nil,
      entries: [],
      counts: nil,
      loading: false,
      request_log: [],
      error_message: nil,
      origin_settings: [],
      origin_bots: [],
      write_tokens: [],
      last_token_result: nil,
      setting_form_key: "review_access",
      setting_form_value: "open",
      setting_form_open: false
    )
    |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="x-sandbox min-h-screen bg-gray-50 py-8">
      <div class="px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Origin Console</h1>
        <p class="text-sm text-gray-600 mb-6">
          Moderation, settings, bots, and write tokens — all as the origin identity
        </p>

        <div
          :if={@error_message}
          class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between"
        >
          <span>{@error_message}</span>
          <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
        </div>

        <div class="space-y-6">
          {render_identity_section(assigns)}
          <%= if @verification == :ok do %>
            {render_queue_section(assigns)}
            {Settings.render_settings_section(assigns)}
            {ReviewBot.render_bot_section(assigns)}
            {WriteToken.render_token_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event(event, params, socket) when event in @manage_events do
    Manage.handle_event(event, params, socket, public_url(socket))
  end

  def handle_event("validate_key_file", _params, socket), do: socket |> noreply()

  def handle_event("import_identity", _params, socket) do
    [content] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Identity.parse(content) do
      {:ok, identity} ->
        verify_identity_async(identity, public_url(socket))

        socket
        |> assign(identity: identity, error_message: nil, loading: true)
        |> noreply()

      {:error, reason} ->
        socket
        |> assign(error_message: "Import failed: #{reason}")
        |> noreply()
    end
  end

  def handle_event("refresh", _params, socket) do
    load_queue_async(socket.assigns.identity, public_url(socket))

    socket
    |> assign(loading: true)
    |> noreply()
  end

  def handle_event("publish", %{"hash" => review_hash}, socket) do
    moderate(socket, review_hash, :post_right, "Published")
  end

  def handle_event("revoke", %{"hash" => review_hash}, socket) do
    moderate(socket, review_hash, :revoke_right, "Revoked")
  end

  def handle_event("clear_error", _params, socket) do
    socket
    |> assign(error_message: nil)
    |> noreply()
  end

  # --- Info ---

  @impl true
  def handle_info({:identity_verified, %{verification: :ok} = result}, socket) do
    load_queue_async(socket.assigns.identity, public_url(socket))
    load_manage_async(socket.assigns.identity, public_url(socket))

    socket
    |> assign(
      origin: result.origin,
      origin_card: result.origin_card,
      verification: :ok,
      loading: true
    )
    |> noreply()
  end

  def handle_info({:identity_verified, result}, socket) do
    socket
    |> assign(origin: result.origin, verification: result.verification, loading: false)
    |> noreply()
  end

  def handle_info({:queue_loaded, %{entries: entries, counts: counts}}, socket) do
    socket
    |> assign(entries: entries, counts: counts, loading: false)
    |> noreply()
  end

  def handle_info({:manage_loaded, manage_data}, socket) do
    socket
    |> assign(
      origin_settings: manage_data.origin_settings,
      origin_bots: manage_data.origin_bots,
      write_tokens: manage_data.write_tokens
    )
    |> noreply()
  end

  def handle_info({:load_failed, reason}, socket) do
    socket
    |> assign(error_message: reason, loading: false)
    |> noreply()
  end

  # --- Private ---

  defp moderate(socket, review_hash, right_key, action_label) do
    %{identity: identity, entries: entries} = socket.assigns
    entry = Enum.find(entries, &(&1.review_hash == review_hash))

    case ApiClient.moderate(identity, entry && Map.get(entry, right_key), public_url(socket)) do
      {:ok, %{log_entries: logs}} ->
        load_queue_async(identity, public_url(socket))

        socket
        |> append_logs(logs ++ [%{label: "#{action_label} #{review_hash}", status: :ok}])
        |> assign(loading: true)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> append_logs(logs)
        |> assign(error_message: reason)
        |> noreply()
    end
  end

  defp verify_identity_async(identity, base_url) do
    pid = self()
    auth = Manage.origin_auth(identity)

    async(pid, fn ->
      %{origin: origin, card: card} =
        Queue.fetch_origin_context(identity.origin_hash, base_url, auth)

      verification = Identity.verify_against_card(identity, card)

      origin_card =
        if card do
          %{
            sign_pkey: Crypto.decode_binary_field(card["sign_pkey"]),
            crypt_pkey: Crypto.decode_binary_field(card["crypt_pkey"])
          }
        end

      send(
        pid,
        {:identity_verified,
         %{origin: origin, origin_card: origin_card, verification: verification}}
      )
    end)
  end

  defp load_queue_async(identity, base_url) do
    pid = self()
    auth = Manage.origin_auth(identity)

    async(pid, fn ->
      result = Queue.load(identity.origin_hash, identity.crypt_skey, base_url, auth)
      send(pid, {:queue_loaded, result})
    end)
  end

  defp load_manage_async(identity, base_url) do
    pid = self()

    async(pid, fn ->
      result = Manage.load_all(identity, base_url)
      send(pid, {:manage_loaded, result})
    end)
  end

  defp async(pid, fun) do
    Task.start(fn ->
      try do
        fun.()
      rescue
        error -> send(pid, {:load_failed, "Shape read failed: #{Exception.message(error)}"})
      end
    end)
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))
end
