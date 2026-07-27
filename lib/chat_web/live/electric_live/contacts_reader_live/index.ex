defmodule ChatWeb.ElectricLive.ContactsReaderLive.Index do
  @moduledoc "Sandbox for reading reviews as a contact — own review_list + peers' via dialog keys."

  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.ContactsReaderLive.Render

  alias ChatWeb.ElectricLive.ContactsReaderLive.KeyScanner
  alias ChatWeb.ElectricLive.ContactsReaderLive.ReviewReader
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ListPassword

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      user: nil,
      contacts: %{},
      own_key: nil,
      selected_source: nil,
      review_list_entries: [],
      decrypted_reviews: [],
      public_passwords: %{},
      loading: false,
      error_message: nil,
      request_log: []
    )
    |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)
    |> ok()
  end

  @impl true
  def render(assigns), do: render_page(assigns)

  # --- Events ---

  @impl true
  def handle_event("validate_key_file", _params, socket), do: noreply(socket)

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} -> socket |> load_user(user_data) |> noreply()
      {:error, reason} -> socket |> assign(error_message: "Import failed: #{reason}") |> noreply()
    end
  end

  def handle_event("scan_dialogs", _params, socket) do
    %{user: user} = socket.assigns
    base_url = public_url(socket)

    case KeyScanner.scan(user, base_url) do
      {:ok, %{contacts: contacts, log_entries: logs}} ->
        socket |> assign(contacts: contacts) |> append_logs(logs) |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("select_source", %{"source" => source}, socket) do
    socket |> assign(selected_source: source, loading: true) |> noreply()
  end

  def handle_event("load_reviews", _params, socket) do
    %{selected_source: source, user: user, own_key: own_key, contacts: contacts} = socket.assigns
    base_url = public_url(socket)
    pid = self()

    {user_hash, list_password} =
      case source do
        "own" -> {user.user_hash, own_key}
        peer_hash -> {peer_hash, Map.fetch!(contacts, peer_hash)}
      end

    Task.start_link(fn ->
      case ReviewReader.read(user_hash, list_password, base_url) do
        {:ok, result} -> send(pid, {:reviews_loaded, result})
        {:error, reason} -> send(pid, {:reviews_error, reason})
      end
    end)

    noreply(socket)
  end

  def handle_event("clear_error", _params, socket) do
    socket |> assign(error_message: nil) |> noreply()
  end

  # --- Info ---

  @impl true
  def handle_info({:reviews_loaded, result}, socket) do
    socket
    |> assign(
      review_list_entries: result.entries,
      decrypted_reviews: result.reviews,
      public_passwords: result.public_passwords,
      loading: false
    )
    |> append_logs(result.log_entries)
    |> noreply()
  end

  def handle_info({:reviews_error, reason}, socket) do
    socket |> assign(error_message: reason, loading: false) |> noreply()
  end

  # --- Private ---

  defp load_user(socket, user_data) do
    case ListPassword.load_or_create(user_data, public_url(socket)) do
      {:ok, password, logs} ->
        socket
        |> assign(user: user_data, own_key: password, error_message: nil)
        |> append_logs(logs)

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(user: user_data, error_message: "No own review_list_password: #{reason}")
        |> append_logs(logs)
    end
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))
end
