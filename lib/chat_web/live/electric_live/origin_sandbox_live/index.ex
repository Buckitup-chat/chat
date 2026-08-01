defmodule ChatWeb.ElectricLive.OriginSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing origin owner operations via Electric API."

  use ChatWeb, :live_view

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.OriginSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.OriginSandboxLive.Render

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
    base_url = public_url(socket)
    owner = socket.assigns.owner

    case ApiClient.create_origin(owner, name, mode, base_url) do
      {:ok, %{origin: origin, log_entries: logs}} ->
        {:noreply, socket |> assign(origin: origin) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("update_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = public_url(socket)
    %{origin: origin} = socket.assigns

    case ApiClient.update_origin(origin, name, mode, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        {:noreply, socket |> assign(origin: updated) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("delete_origin", _params, socket) do
    base_url = public_url(socket)
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
  def render(assigns), do: Render.render_page(assigns)
end
