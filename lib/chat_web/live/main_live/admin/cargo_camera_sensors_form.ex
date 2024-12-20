defmodule ChatWeb.MainLive.Admin.CargoCameraSensorsForm do
  @moduledoc """
  Handles showing and updating camera sensors settings form data.
  """
  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.CargoSettings
  alias Chat.AdminRoom
  alias Chat.Sync.Camera.Sensor

  alias ChatWeb.MainLive.Admin.CameraPreview

  def mount(socket) do
    cargo_settings = AdminRoom.get_cargo_settings()

    socket
    |> assign(:cargo_settings, cargo_settings)
    |> assign(:changeset, cargo_settings |> CargoSettings.camera_sensors_changeset())
    |> assign(:invalid_sensors, %{})
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="mt-3">
      <.form
        :let={form}
        for={@changeset}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
        class="camera-sensor-input-form"
      >
        <fieldset class="flex flex-col space-y-2">
          <%= for {url, index} <- form_input_list(form) do %>
            <div class="camera-sensor flex flex-row">
              <.live_component module={CameraPreview} id={"camera-sensor-preview-#{index}"} url={url} />
              <input
                id={"camera-sensor-input-#{index}"}
                class={
                  classes(
                    "camera-sensor-input w-full ml-1 bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent",
                    %{
                      "focus:ring-red-500 ring-red-500 focus:border-red-500 border-red-500" =>
                        Map.has_key?(@invalid_sensors, index)
                    }
                  )
                }
                type="text"
                placeholder="Paste the url here"
                value={url}
                name={index}
                phx-debounce="500"
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
            <%= if Map.has_key?(@invalid_sensors, index) do %>
              <div class="flex-row text-xs text-red-500">
                {Map.get(@invalid_sensors, index)}
              </div>
            <% end %>
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
        {submit("Update",
          class:
            "h-11 w-full px-10 mt-4 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center disabled:opacity-50",
          disabled: !@changeset.valid? or !Enum.empty?(@invalid_sensors),
          phx_disable_with: "Updating..."
        )}
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
        %{"index" => index_str, "url" => _url},
        %{
          assigns: %{
            cargo_settings: settings,
            changeset: changeset
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
    |> forget_invalid_sensor(index_str)
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
    |> validate_sensor(url, index)
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

  defp validate_sensor(socket, url, index) do
    case Sensor.get_image(url) do
      {:ok, _} ->
        socket |> forget_invalid_sensor(index)

      {:error, error_message} ->
        socket |> add_invalid_sensor(index, error_message)
    end
  end

  defp add_invalid_sensor(
         %{assigns: %{invalid_sensors: invalid_sensors}} = socket,
         index,
         message
       )
       when is_integer(index) do
    assign(socket, :invalid_sensors, invalid_sensors |> Map.put(index, message))
  end

  defp forget_invalid_sensor(%{assigns: %{invalid_sensors: invalid_sensors}} = socket, index)
       when is_integer(index) do
    {keep_index, to_reindex} = Enum.split_with(invalid_sensors, fn {key, _} -> key <= index end)

    reindexed =
      to_reindex
      |> Enum.map(fn {k, v} -> {k - 1, v} end)
      |> Map.new()

    keep_index
    |> Map.new()
    |> Map.delete(index)
    |> Map.merge(reindexed)
    |> then(&assign(socket, :invalid_sensors, &1))
  end

  defp forget_invalid_sensor(socket, index_str),
    do: forget_invalid_sensor(socket, String.to_integer(index_str))
end
