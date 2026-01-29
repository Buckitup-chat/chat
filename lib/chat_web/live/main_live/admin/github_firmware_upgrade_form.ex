defmodule ChatWeb.MainLive.Admin.GithubFirmwareUpgradeForm do
  @moduledoc "Firmware upgrade from GitHub releases"
  use ChatWeb, :live_component

  alias Phoenix.PubSub

  @github_releases_url "https://api.github.com/repos/Buckitup-chat/platform/releases"
  @outgoing_topic Application.compile_env!(:chat, :topic_to_platform)

  def mount(socket) do
    socket
    |> assign(:substep, :loading)
    |> assign(:releases, [])
    |> assign(:selected_release, nil)
    |> assign(:download_progress, 0)
    |> assign(:error_message, nil)
    |> ok()
  end

  def update(assigns, socket) do
    assigns
    |> case do
      %{platform_response: response} ->
        socket |> handle_platform_response(response)

      %{fetched_releases: {:error, message}} ->
        socket
        |> assign(:substep, :error)
        |> assign(:error_message, message)

      %{fetched_releases: []} ->
        socket
        |> assign(:substep, :error)
        |> assign(:error_message, "No firmware releases found")

      %{fetched_releases: releases} when is_list(releases) ->
        socket
        |> assign(:substep, :ready)
        |> assign(:releases, releases)
        |> assign(:selected_release, List.first(releases))

      %{action: :start_download} ->
        socket |> start_download()

      other ->
        socket
        |> assign(other)
        |> maybe_fetch_releases()
    end
    |> ok()
  end

  defp maybe_fetch_releases(%{assigns: %{substep: :loading}} = socket) do
    fetch_releases_async(socket.assigns.id)
    socket
  end

  defp maybe_fetch_releases(socket), do: socket

  defp fetch_releases_async(component_id) do
    Task.start(fn ->
      result = fetch_releases()

      send_update(
        __MODULE__,
        id: component_id,
        fetched_releases: result
      )
    end)
  end

  defp fetch_releases do
    Req.get!(@github_releases_url, headers: [{"user-agent", "BuckitUp-Chat"}])
    |> Map.get(:body)
    |> Enum.map(&parse_release/1)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> {:error, "Failed to fetch releases"}
  end

  defp parse_release(%{"tag_name" => tag, "assets" => assets}) do
    assets
    |> Enum.find(&fw_asset?/1)
    |> case do
      %{"browser_download_url" => url} -> %{tag: tag, url: url}
      _ -> nil
    end
  end

  defp parse_release(_), do: nil

  defp fw_asset?(%{"name" => name}), do: String.ends_with?(name, ".fw")
  defp fw_asset?(_), do: false

  defp handle_platform_response(socket, {:github_firmware_upgrade, payload}) do
    case payload do
      {:download_progress, percent} when percent >= 100 ->
        socket
        |> assign(:substep, :upgrading)
        |> assign(:download_progress, 100)

      {:download_progress, percent} ->
        socket
        |> assign(:download_progress, percent)

      :done ->
        socket
        |> assign(:substep, :ready)
        |> assign(:download_progress, 0)

      {:error, reason} ->
        socket
        |> assign(:substep, :error)
        |> assign(:error_message, "Upgrade failed: #{inspect(reason)}")
    end
  end

  def render(%{substep: :loading} = assigns) do
    ~H"""
    <div class="text-center p-2">
      Loading releases...
    </div>
    """
  end

  def render(%{substep: :error} = assigns) do
    ~H"""
    <div>
      <div class="text-red-500 p-2">{@error_message}</div>
      <button
        class="w-full h-11 mt-2 bg-grayscale text-white py-2 px-4 rounded-lg"
        phx-click="retry-fetch"
        phx-target={@myself}
      >
        Retry
      </button>
    </div>
    """
  end

  def render(%{substep: :ready} = assigns) do
    ~H"""
    <div>
      <.form for={%{}} as={:github_firmware} phx-change="select-release" phx-target={@myself}>
        <select name="release" class="w-full p-2 rounded bg-white/50">
          <%= for release <- @releases do %>
            <option value={release.tag} selected={release.tag == @selected_release.tag}>
              {release.tag}
            </option>
          <% end %>
        </select>
      </.form>
      <button
        class="w-full h-11 mt-2 bg-grayscale text-white py-2 px-4 rounded-lg"
        phx-click="install-release"
        phx-target={@myself}
      >
        Install
      </button>
    </div>
    """
  end

  def render(%{substep: :downloading} = assigns) do
    ~H"""
    <div>
      <div class="p-2">Downloading firmware...</div>
      <div class="mt-2 w-full flex flex-row items-center space-x-2">
        <progress class="w-full" value={@download_progress} max="100">
          {@download_progress}%
        </progress>
        <span class="text-sm">{@download_progress}%</span>
      </div>
    </div>
    """
  end

  def render(%{substep: :upgrading} = assigns) do
    ~H"""
    <div class="p-2">
      Applying firmware upgrade... <br /> The reboot will be performed automatically.
    </div>
    """
  end

  def handle_event("select-release", %{"release" => tag}, socket) do
    selected =
      socket.assigns.releases
      |> Enum.find(&(&1.tag == tag))

    socket
    |> assign(:selected_release, selected)
    |> noreply()
  end

  def handle_event("install-release", _, socket) do
    send(
      self(),
      {:admin, {:github_upgrade_firmware_confirmation, socket.assigns.selected_release}}
    )

    socket |> noreply()
  end

  def handle_event("retry-fetch", _, socket) do
    fetch_releases_async(socket.assigns.id)

    socket
    |> assign(:substep, :loading)
    |> assign(:error_message, nil)
    |> noreply()
  end

  def start_download(socket) do
    selected = socket.assigns.selected_release

    PubSub.broadcast(Chat.PubSub, @outgoing_topic, {:upgrade_firmware_from_url, selected.url})

    socket
    |> assign(:substep, :downloading)
    |> assign(:download_progress, 0)
  end
end
