defmodule ChatWeb.MainLive.Admin.MediaSettingsForm do
  @moduledoc """
  Handles showing and updating media settings form data.
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.MediaSettings
  alias Chat.AdminRoom

  @impl Phoenix.LiveComponent
  def mount(socket) do
    media_settings = AdminRoom.get_media_settings()
    changeset = MediaSettings.changeset(media_settings, %{})

    {:ok,
     socket
     |> assign(:changeset, changeset)
     |> assign(:media_settings, media_settings)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"media_settings" => params}, socket) do
    changeset =
      %MediaSettings{}
      |> MediaSettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"media_settings" => params}, socket) do
    changeset =
      %MediaSettings{}
      |> MediaSettings.changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      :ok =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> AdminRoom.store_media_settings()
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
        id="media_settings"
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <div>
          When new USB drive is plugged into the secondary port,<br />
          the following functionality will be started:
        </div>
        <%= for {value, label} <- Ecto.Enum.mappings(MediaSettings, :functionality) do %>
          <.functionality_radio_button form={f} label={label} value={value} />
        <% end %>
        <%= error_tag(f, :functionality) %>

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

  defp functionality_radio_button(assigns) do
    ~H"""
    <div class="flex items-center">
      <%= label do %>
        <%= radio_button(@form, :functionality, @value) %>

        <span class={"ml-2 text-sm" <> if(selected_functionality?(@form, @value), do: " font-bold", else: "")}>
          <%= @label %>
        </span>
      <% end %>
    </div>
    """
  end

  defp selected_functionality?(form, value) do
    selected_value =
      form
      |> input_value(:functionality)
      |> maybe_convert_to_atom()

    selected_value == value
  end

  defp maybe_convert_to_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp maybe_convert_to_atom(value), do: value
end
