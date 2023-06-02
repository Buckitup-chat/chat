defmodule ChatWeb.MainLive.Admin.CargoCameraSensorsForm do
  @moduledoc """
  Handles showing and updating camera sensors settings form data.
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.CargoSettings
  alias Chat.AdminRoom

  def mount(socket) do
    cargo_settings = AdminRoom.get_cargo_settings()

    socket
    |> assign(:cargo_settings, cargo_settings)
    |> assign(:changeset, cargo_settings |> CargoSettings.camera_sensors_changeset())
    |> assign(:invalid_sensors, [])
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="mt-3">
      <.form :let={form} for={@changeset} phx-change="validate" phx-submit="save" phx-target={@myself}>
        <fieldset class="flex flex-col space-y-2">
          <%= for {url, index} <- form_input_list(form) do %>
            <div class="flex flex-row">
              <.camera_img url={url} />
              <input
                id={"camera-sensor-input-#{index}"}
                class={
                  classes(
                    "w-full ml-1 bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent",
                    %{
                      "focus:ring-red-500 ring-red-500 focus:border-red-500 border-red-500" =>
                        Enum.member?(@invalid_sensors, url)
                    }
                  )
                }
                type="text"
                placeholder="Paste the url here"
                value={url}
                name={index}
                phx-debounce="2000"
              />
              <button
                class="pl-2"
                type="button"
                phx-click="delete"
                phx-value-index={index}
                phx-value-url={url}
                phx-target={@myself}
              >
                <.icon id="close" class="w-4 h-4 fill-gray-500 " />
              </button>
            </div>
          <% end %>
          <button
            class="mx-auto mt-3 flex flex-row "
            type="button"
            phx-click="add"
            phx-target={@myself}
          >
            <.icon id="add" class="w-4 h-4 mt-1 fill-grayscale items-center justify-center" /> Add
          </button>
          <%= unless Enum.empty?(@invalid_sensors) do %>
            <div class="mt-3 w-full h-7 flex flex-row items-center border-0 rounded-lg bg-black/10">
              <.icon id="alert" class="ml-1 w-4 h-4 fill-black/40" />
              <blockquote class="ml-1 text-xs text-black/50 ">
                Please remove invalid sensors.
              </blockquote>
            </div>
          <% end %>
        </fieldset>
        <%= submit("Update",
          class:
            "h-11 w-full px-10 mt-4 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center disabled:opacity-50",
          disabled: !@changeset.valid? or !Enum.empty?(@invalid_sensors),
          phx_disable_with: "Updating..."
        ) %>
      </.form>
    </div>
    """
  end

  def handle_event("add", _, %{assigns: assigns} = socket) do
    %{cargo_settings: settings} = assigns
    %{changeset: changeset} = assigns
    sensors = changeset |> CargoSettings.camera_sensors_field()

    socket
    |> assign(
      :changeset,
      CargoSettings.camera_sensors_changeset(settings, %{camera_sensors: sensors ++ [""]})
    )
    |> noreply()
  end

  def handle_event(
        "delete",
        %{"index" => index_str, "url" => url},
        %{
          assigns: %{
            cargo_settings: settings,
            changeset: changeset,
            invalid_sensors: invalid_sensors
          }
        } = socket
      ) do
    sensors = changeset |> CargoSettings.camera_sensors_field()

    case sensors do
      [_] ->
        socket
        |> assign(:changeset, changeset |> CargoSettings.reset_camera_sensors())

      _ ->
        socket
        |> assign(
          :changeset,
          CargoSettings.camera_sensors_changeset(settings, %{
            camera_sensors: List.delete_at(sensors, String.to_integer(index_str))
          })
        )
    end
    |> assign(:invalid_sensors, invalid_sensors |> List.delete(url))
    |> noreply()
  end

  def handle_event("validate", %{"_target" => [target]} = params, %{assigns: assigns} = socket) do
    url = params[target] |> String.trim()
    index = String.to_integer(target)

    %{cargo_settings: settings} = assigns
    %{changeset: changeset} = assigns
    sensors = changeset |> CargoSettings.camera_sensors_field()

    socket
    |> assign(
      :changeset,
      CargoSettings.camera_sensors_changeset(settings, %{
        camera_sensors: List.replace_at(sensors, index, url)
      })
    )
    |> validate_sensor(url)
    |> noreply()
  end

  def handle_event("save", _, %{assigns: %{changeset: changeset}} = socket) do
    :ok = changeset |> Ecto.Changeset.apply_changes() |> AdminRoom.store_cargo_settings()

    send(self(), :update_backup_settings)

    socket
    |> noreply()
  end

  defp form_input_list(%Phoenix.HTML.Form{source: changeset}) do
    changeset
    |> CargoSettings.camera_sensors_field()
    |> Enum.with_index()
  end

  defp camera_img(assigns) do
    ~H"""
    <%= if @url != "" do %>
      <img class="w-12" src={@url} />
    <% end %>
    """
  end

  defp validate_sensor(%{assigns: %{invalid_sensors: invalid_sensors}} = socket, url) do
    with %{scheme: scheme} when scheme in ["http", "https"] <- URI.parse(url),
         {:ok, %{status_code: 200}} <- HTTPoison.get(url) do
      socket
    else
      _ -> socket |> assign(:invalid_sensors, [url | invalid_sensors])
    end
  end
end
