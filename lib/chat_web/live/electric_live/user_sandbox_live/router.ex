defmodule ChatWeb.ElectricLive.UserSandboxLive.Router do
  @moduledoc "Event handlers for the User Sandbox LiveView."

  import Phoenix.Component
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, push_event: 3]

  alias ChatWeb.ElectricLive.UserSandboxLive.{ApiClient, Components, Identity}

  def handle_event("create_user", %{"name" => name}, socket) do
    base_url = get_base_url(socket)
    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.create_user(name, base_url) do
      {:ok, %{user: user_data, log_entries: log_entries}} ->
        socket =
          socket
          |> assign(user: user_data, storage_items: [])
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(operation_in_progress: false, error_message: nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(
            operation_in_progress: false,
            error_message: "Failed to create user: #{reason}"
          )

        {:noreply, socket}
    end
  end

  def handle_event("update_name", %{"new_name" => new_name}, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user
    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.update_user_name(user, user.sign_skey, new_name, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        updated_user = %{user | name: new_name, owner_timestamp: user.owner_timestamp + 1}

        socket =
          socket
          |> assign(:user, updated_user)
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(operation_in_progress: false, error_message: nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(
            operation_in_progress: false,
            error_message: "Failed to update name: #{reason}"
          )

        {:noreply, socket}
    end
  end

  def handle_event("delete_user", _params, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user
    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.delete_user(user.user_hash, user.sign_skey, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        socket =
          socket
          |> assign(user: nil, storage_items: [])
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(operation_in_progress: false, error_message: nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(
            operation_in_progress: false,
            error_message: "Failed to delete user: #{reason}"
          )

        {:noreply, socket}
    end
  end

  def handle_event("show_create_storage_form", _params, socket) do
    {:noreply, assign(socket, show_storage_form: true, editing_storage_uuid: nil)}
  end

  def handle_event("edit_storage", %{"uuid" => uuid}, socket) do
    {:noreply, assign(socket, show_storage_form: true, editing_storage_uuid: uuid)}
  end

  def handle_event("hide_storage_form", _params, socket) do
    {:noreply, assign(socket, show_storage_form: false, editing_storage_uuid: nil)}
  end

  def handle_event("view_storage_details", %{"uuid" => uuid}, socket) do
    {:noreply, assign(socket, viewing_storage_uuid: uuid)}
  end

  def handle_event("hide_storage_details", _params, socket) do
    {:noreply, assign(socket, viewing_storage_uuid: nil)}
  end

  def handle_event("create_storage", params, socket) do
    %{"size" => size_str, "label" => label} = params
    uuid = Map.get(params, "uuid", "")
    base_url = get_base_url(socket)
    user = socket.assigns.user

    uuid = if uuid == "", do: Ecto.UUID.generate(), else: uuid
    size = String.to_integer(size_str)
    value_b64 = generate_storage_value(size)
    value_binary = Base.decode64!(value_b64)

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.create_storage(user.user_hash, user.sign_skey, uuid, value_binary, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        new_item = %{
          uuid: uuid,
          value_b64: value_b64,
          size: size,
          label: if(label == "", do: nil, else: label)
        }

        socket =
          socket
          |> update(:storage_items, &[new_item | &1])
          |> assign(:show_storage_form, false)
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(operation_in_progress: false, error_message: nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(
            operation_in_progress: false,
            error_message: "Failed to create storage: #{reason}"
          )

        {:noreply, socket}
    end
  end

  def handle_event(
        "save_storage_edit",
        %{"uuid" => uuid, "size" => size_str, "label" => label},
        socket
      ) do
    base_url = get_base_url(socket)
    user = socket.assigns.user
    size = String.to_integer(size_str)
    value_b64 = generate_storage_value(size)
    value_binary = Base.decode64!(value_b64)

    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.update_storage(user.user_hash, user.sign_skey, uuid, value_binary, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        updated_label = if(label == "", do: nil, else: label)

        socket =
          socket
          |> update(
            :storage_items,
            &update_storage_item(&1, uuid, value_b64, size, updated_label)
          )
          |> assign(show_storage_form: false, editing_storage_uuid: nil)
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(operation_in_progress: false, error_message: nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(
            operation_in_progress: false,
            error_message: "Failed to update storage: #{reason}"
          )

        {:noreply, socket}
    end
  end

  def handle_event("delete_storage", %{"uuid" => uuid}, socket) do
    base_url = get_base_url(socket)
    user = socket.assigns.user
    socket = assign(socket, :operation_in_progress, true)

    case ApiClient.delete_storage(user.user_hash, user.sign_skey, uuid, base_url) do
      {:ok, %{log_entries: log_entries}} ->
        socket =
          socket
          |> update(:storage_items, &Enum.reject(&1, fn item -> item.uuid == uuid end))
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(operation_in_progress: false, error_message: nil)

        {:noreply, socket}

      {:error, %{reason: reason, log_entries: log_entries}} ->
        socket =
          socket
          |> update(:request_log, &(&1 ++ log_entries))
          |> assign(
            operation_in_progress: false,
            error_message: "Failed to delete storage: #{reason}"
          )

        {:noreply, socket}
    end
  end

  def handle_event("export_keys", _params, socket) do
    user = socket.assigns.user
    filename = "identity_#{Components.short_hash(user.user_hash_hex)}.json"

    {:noreply,
     push_event(socket, "download_file", %{data: Identity.to_json(user), filename: filename})}
  end

  def handle_event("toggle_docs", _params, socket) do
    {:noreply, assign(socket, :show_docs, !socket.assigns.show_docs)}
  end

  def handle_event("toggle_doc_section", %{"section" => section}, socket) do
    expanded_docs =
      if section in socket.assigns.expanded_docs do
        MapSet.delete(socket.assigns.expanded_docs, section)
      else
        MapSet.put(socket.assigns.expanded_docs, section)
      end

    {:noreply, assign(socket, :expanded_docs, expanded_docs)}
  end

  def handle_event("clear_log", _params, socket) do
    {:noreply, assign(socket, :request_log, [])}
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    socket =
      case Identity.parse_and_validate(result) do
        {:ok, user_data} ->
          assign(socket, user: user_data, storage_items: [], error_message: nil)

        {:error, reason} ->
          assign(socket, :error_message, "Import failed: #{reason}")
      end

    {:noreply, socket}
  end

  defp get_base_url(socket) do
    uri = socket.host_uri
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end

  defp update_storage_item(items, uuid, value_b64, size, label) do
    Enum.map(items, fn
      %{uuid: ^uuid} = item -> %{item | value_b64: value_b64, size: size, label: label}
      item -> item
    end)
  end

  defp generate_storage_value(size) do
    :crypto.strong_rand_bytes(size) |> Base.encode64()
  end
end
