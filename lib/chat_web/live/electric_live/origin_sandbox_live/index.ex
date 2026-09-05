defmodule ChatWeb.ElectricLive.OriginSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing origin owner operations via Electric API."

  use ChatWeb, :live_view

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.OriginSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.OriginSandboxLive.Render

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        owner: nil,
        origin: nil,
        origins: [],
        request_log: [],
        error_message: nil,
        pending_reviews: nil
      )
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
        base_url = public_url(socket)
        origins = ApiClient.list_owner_origins(user_data.user_hash, base_url)
        {:noreply, assign(socket, owner: user_data, origins: origins, error_message: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Import failed: #{reason}")}
    end
  end

  def handle_event("create_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = public_url(socket)
    owner = socket.assigns.owner

    case ApiClient.create_origin(owner, name, mode, base_url) do
      {:ok, %{origin: origin, log_entries: logs}} ->
        origins = ApiClient.list_owner_origins(owner.user_hash, base_url)
        pending = ApiClient.has_pending_reviews?(origin.origin_hash, base_url)

        {:noreply,
         socket
         |> assign(origin: origin, origins: origins, pending_reviews: pending)
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("select_origin", %{"hash" => hash}, socket) do
    base_url = public_url(socket)

    case Enum.find(socket.assigns.origins, &(&1.origin_hash == hash)) do
      nil ->
        {:noreply, socket}

      found ->
        pending = ApiClient.has_pending_reviews?(hash, base_url)
        {:noreply, assign(socket, origin: found, pending_reviews: pending)}
    end
  end

  def handle_event("refresh_origins", _params, socket) do
    base_url = public_url(socket)
    origins = ApiClient.list_owner_origins(socket.assigns.owner.user_hash, base_url)
    origin = refresh_selected_origin(socket.assigns.origin, origins)
    {:noreply, assign(socket, origins: origins, origin: origin)}
  end

  def handle_event("refresh_pending_reviews", _params, socket) do
    base_url = public_url(socket)
    %{origin: origin} = socket.assigns
    pending = ApiClient.has_pending_reviews?(origin.origin_hash, base_url)
    {:noreply, assign(socket, pending_reviews: pending)}
  end

  def handle_event("update_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = public_url(socket)
    %{origin: origin, owner: owner} = socket.assigns

    case ApiClient.update_origin(origin, owner, name, mode, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        origins = update_in_list(socket.assigns.origins, updated)
        {:noreply, socket |> assign(origin: updated, origins: origins) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("delete_origin", _params, socket) do
    base_url = public_url(socket)
    %{origin: origin, owner: owner} = socket.assigns

    case ApiClient.delete_origin(origin, owner, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        origins = update_in_list(socket.assigns.origins, updated)
        {:noreply, socket |> assign(origin: updated, origins: origins) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("export_origin_identity", _params, socket) do
    origin = socket.assigns.origin
    filename = "origin_identity_#{Shortcode.short_code(origin.origin_hash)}.json"

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

  defp refresh_selected_origin(nil, _origins), do: nil

  defp refresh_selected_origin(current, origins) do
    case Enum.find(origins, &(&1.origin_hash == current.origin_hash)) do
      nil -> nil
      found -> Map.merge(found, Map.take(current, [:origin_sign_skey, :origin_crypt_skey]))
    end
  end

  defp update_in_list(origins, updated) do
    Enum.map(origins, fn o ->
      if o.origin_hash == updated.origin_hash, do: updated, else: o
    end)
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  @impl true
  def render(assigns), do: Render.render_page(assigns)
end
