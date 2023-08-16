defmodule ChatWeb.MainLive.Admin.FirmwareUpgradeForm do
  @moduledoc "Firmwares upload and upgrade"
  use ChatWeb, :live_component

  alias Phoenix.PubSub

  @upload_options [
    accept: ~w(.fw),
    max_entries: 1,
    max_file_size: 1_024_000_000,
    auto_upload: true,
    progress: &__MODULE__.handle_progress/3
  ]
  @outgoing_topic "chat->platform"

  def update(assigns, socket) do
    socket
    |> assign(:step, :upload)
    |> assign(:substep, :pending)
    |> assign(assigns)
    |> handle_upload()
    |> handle_upgrade()
    |> ok()
  end

  defp handle_upload(%{assigns: %{step: :upload}} = socket) do
    socket |> allow_upload(:config, @upload_options)
  end

  defp handle_upload(socket), do: socket

  defp handle_upgrade(%{assigns: %{step: :upgrade}} = socket) do
    consume_uploaded_entries(socket, :config, fn %{path: path}, _entry ->
      content = File.read!(path)
      PubSub.broadcast(Chat.PubSub, @outgoing_topic, {:upgrade_firmware, content})
      {:ok, path}
    end)

    socket
  end

  defp handle_upgrade(socket), do: socket

  def render(%{step: :upload} = assigns) do
    ~H"""
    <div>
      <.form
        for={%{}}
        as={:platform_firmware}
        id="firmware-upgrade-form"
        class="column"
        phx-change="upload"
        phx-drop-target={@uploads.config.ref}
        phx-target={@myself}
      >
        <%= live_file_input(@uploads.config, style: "display: none") %>
        <%= if @substep == :pending do %>
          <input
            style="background-color: rgb(36, 24, 36);"
            class="w-full h-11 mt-2 bg-transparent text-white py-2 px-4 border border-white/0 rounded-lg flex items-center justify-center"
            type="button"
            value="Upload"
            onclick="event.target.parentNode.querySelector('input[type=file]').click()"
          />
        <% end %>
      </.form>
      <%= if @substep in [:inprogress, :done]  do %>
        <%= for entry <- @uploads.config.entries do %>
          <div class="mt-4 w-full flex flex-row justify-between space-x-2">
            <progress class="w-full" value={entry.progress} max="100">
              <%= entry.progress %>%
            </progress>
            <button phx-click="cancel-upload" phx-value-ref={entry.ref} phx-target={@myself}>
              <.icon id="close" class="w-5 h-5 flex fill-grayscale" />
            </button>
          </div>
        <% end %>
      <% end %>
      <%= if @substep == :done do %>
        <button
          class="w-full h-11 mt-2 bg-grayscale text-white py-2 px-4 border border-white/0 rounded-lg flex items-center justify-center"
          phx-click="upgrade"
          phx-target={@myself}
        >
          Upgrade
        </button>
      <% end %>
    </div>
    """
  end

  def render(%{step: :upgrade} = assigns) do
    ~H"""
    <div>
      Upgrading... <br /> The reboot will be performed automatically.
    </div>
    """
  end

  def handle_event("upload", _params, socket) do
    socket
    |> assign(:substep, :inprogress)
    |> noreply()
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    socket
    |> cancel_upload(:config, ref)
    |> assign(:substep, :pending)
    |> noreply()
  end

  def handle_event("upgrade", _, socket) do
    send(self(), {:admin, :upgrade_firmware_confirmation})

    socket |> noreply()
  end

  def handle_progress(:config, %{done?: true} = _entry, socket) do
    socket
    |> assign(:substep, :done)
    |> noreply()
  end

  def handle_progress(_file, _entry, socket), do: socket |> noreply()
end
