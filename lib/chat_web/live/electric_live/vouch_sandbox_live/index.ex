defmodule ChatWeb.ElectricLive.VouchSandboxLive.Index do
  @moduledoc "Interactive sandbox for vouch token operations via Electric API."

  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.VouchSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.VouchSandboxLive.Render

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      identity: nil,
      tab: :by_me,
      users: [],
      vouches_by_me: [],
      vouches_for_me: [],
      request_log: [],
      error_message: nil,
      operation_in_progress: false,
      form_subject: "",
      form_kind: ""
    )
    |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)
    |> ok()
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
        base_url = public_url(socket)

        socket
        |> assign(identity: user_data, error_message: nil, users: ApiClient.list_users(base_url))
        |> load_vouches(base_url)
        |> noreply()

      {:error, reason} ->
        socket
        |> assign(error_message: "Import failed: #{reason}")
        |> noreply()
    end
  end

  def handle_event("form_change", params, socket) do
    socket
    |> assign(
      form_subject: params["subject_hash"] || socket.assigns.form_subject,
      form_kind: params["kind"] || socket.assigns.form_kind
    )
    |> noreply()
  end

  def handle_event("create_vouch", %{"subject_hash" => subject, "kind" => kind}, socket) do
    base_url = public_url(socket)
    identity = socket.assigns.identity

    socket = assign(socket, operation_in_progress: true)

    case ApiClient.create_vouch(identity, String.trim(subject), String.trim(kind), base_url) do
      {:ok, %{log_entries: logs}} ->
        socket
        |> assign(operation_in_progress: false, form_subject: "", form_kind: "")
        |> append_logs(logs)
        |> load_vouches(base_url)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: reason, operation_in_progress: false)
        |> append_logs(logs)
        |> noreply()
    end
  end

  def handle_event("revoke_vouch", %{"kind" => kind, "subject" => subject, "timestamp" => ts}, socket) do
    base_url = public_url(socket)
    identity = socket.assigns.identity

    vouch = %{
      kind: kind,
      subject_hash: subject,
      owner_timestamp: String.to_integer(ts)
    }

    socket = assign(socket, operation_in_progress: true)

    case ApiClient.revoke_vouch(identity, vouch, base_url) do
      {:ok, %{log_entries: logs}} ->
        socket
        |> assign(operation_in_progress: false)
        |> append_logs(logs)
        |> load_vouches(base_url)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: reason, operation_in_progress: false)
        |> append_logs(logs)
        |> noreply()
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket |> assign(tab: String.to_existing_atom(tab)) |> noreply()
  end

  def handle_event("refresh_vouches", _params, socket) do
    base_url = public_url(socket)
    socket |> load_vouches(base_url) |> noreply()
  end

  def handle_event("clear_error", _params, socket) do
    socket |> assign(:error_message, nil) |> noreply()
  end

  @impl true
  def render(assigns), do: Render.render_page(assigns)

  defp load_vouches(socket, base_url) do
    hash = socket.assigns.identity.user_hash

    assign(socket,
      vouches_by_me: ApiClient.list_vouches_by_me(hash, base_url),
      vouches_for_me: ApiClient.list_vouches_for_me(hash, base_url)
    )
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))
end
