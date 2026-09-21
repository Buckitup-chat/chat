defmodule ChatWeb.ElectricLive.AdminSandboxLive.Index do
  @moduledoc "Admin sandbox for viewing device info and managing gate mode."

  use ChatWeb, :live_view

  alias Chat.AdminDb
  alias Chat.DeviceId
  alias Chat.Pq.OwnerBootstrap
  alias Chat.Pq.ServerIdentity
  alias ChatWeb.ElectricLive.AdminSandboxLive.Render
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  @valid_gate_modes ~w(open guarded trust)a

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      device_id: DeviceId.id(),
      server_user_hash: server_user_hash(),
      admin_user_hash: admin_user_hash(),
      gate_mode: gate_mode(),
      identity: nil,
      is_admin: false,
      error_message: nil
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
        is_admin = OwnerBootstrap.owner?(user_data.user_hash)

        socket
        |> assign(identity: user_data, is_admin: is_admin, error_message: nil)
        |> noreply()

      {:error, reason} ->
        socket
        |> assign(error_message: "Import failed: #{reason}")
        |> noreply()
    end
  end

  def handle_event("set_gate_mode", %{"mode" => mode_str}, socket) do
    if socket.assigns.is_admin do
      mode = String.to_existing_atom(mode_str)

      if mode in @valid_gate_modes do
        AdminDb.put(:pq_gate_mode, mode)
        {:noreply, assign(socket, gate_mode: mode)}
      else
        {:noreply, assign(socket, error_message: "Invalid mode: #{mode_str}")}
      end
    else
      {:noreply, assign(socket, error_message: "Only admin can change gate mode")}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  @impl true
  def render(assigns), do: Render.render_page(assigns)

  defp gate_mode, do: AdminDb.get(:pq_gate_mode) || :open

  defp admin_user_hash do
    case OwnerBootstrap.owner() do
      %{user_hash: hash} -> hash
      _ -> nil
    end
  end

  defp server_user_hash do
    ServerIdentity.user_hash()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
