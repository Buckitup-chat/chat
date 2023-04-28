defmodule ChatWeb.MainLive.Admin.BackupSettingsForm do
  @moduledoc """
  Handles showing and updating backup settings form data.
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.BackupSettings
  alias Chat.AdminRoom

  @impl Phoenix.LiveComponent
  def mount(socket) do
    backup_settings = AdminRoom.get_backup_settings()
    changeset = BackupSettings.changeset(backup_settings, %{})

    {:ok,
     socket
     |> assign(:changeset, changeset)
     |> assign(:backup_settings, backup_settings)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"backup_settings" => params}, socket) do
    changeset =
      %BackupSettings{}
      |> BackupSettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"backup_settings" => params}, socket) do
    changeset =
      %BackupSettings{}
      |> BackupSettings.changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      :ok =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> AdminRoom.store_backup_settings()

      send(self(), :update_backup_settings)
    end

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <section>
      <.form
        :let={f}
        for={@changeset}
        id="backup_settings"
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <div>Should backup finish after copying data or continue syncing?</div>
        <%= for {value, label} <- Ecto.Enum.mappings(BackupSettings, :type) do %>
          <.type_radio_button form={f} label={label} value={value} />
        <% end %>
        <%= error_tag(f, :type) %>

        <%= submit("Update",
          class:
            "h-11 px-10 mt-2 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center",
          disabled: !@changeset.valid?,
          phx_disable_with: "Updating..."
        ) %>
      </.form>
    </section>
    """
  end

  defp type_radio_button(assigns) do
    ~H"""
    <div class="flex items-center">
      <%= label do %>
        <%= radio_button(@form, :type, @value) %>

        <span class={"ml-2 text-sm" <> if(selected_type?(@form, @value), do: " font-bold", else: "")}>
          <%= @label %>
        </span>
      <% end %>
    </div>
    """
  end

  defp selected_type?(form, value) do
    selected_value =
      form
      |> input_value(:type)
      |> maybe_convert_to_atom()

    selected_value == value
  end

  defp maybe_convert_to_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp maybe_convert_to_atom(value), do: value
end
