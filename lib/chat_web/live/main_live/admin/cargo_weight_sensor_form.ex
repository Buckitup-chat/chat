defmodule ChatWeb.MainLive.Admin.CargoWeightSensorForm do
  @moduledoc """
  Handles showing and updating cargo weight sensor settings form data.
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.CargoSettings
  alias Chat.AdminRoom

  def mount(socket) do
    cargo_settings = AdminRoom.get_cargo_settings()
    weight_sensor = cargo_settings.weight_sensor

    with true <- weight_sensor !== %{},
      type <- weight_sensor[:type],
      true <- is_binary(type) and byte_size(type) > 0,
      name <- weight_sensor[:name],
      true <- is_binary(name) and byte_size(name) > 0,
      opts <- Map.drop(weight_sensor, [:name, :type]) |> Map.to_list() do
        test_weight_sensor_connection(type, name, opts)
    end

    socket
    |> assign(:cargo_settings, cargo_settings)
    |> assign(:changeset, CargoSettings.weight_sensor_changeset(cargo_settings.weight_sensor))
    |> assign(:connection_status, "Absent")
    |> assign(:test_message, "---")
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="mt-3">
      <.connection_status status={@connection_status} />
      <.test_message message={@test_message} />
      <.form
        :let={form}
        class="mt-3"
        for={@changeset}
        as={:form}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <div class="flex flex-col">
          <div class="flex flex-col mt-2">
            <%= label(form, :type, "Weight sensor type") %>
            <%= select(form, :type, ["NCI", "Balena D700"],
              selected: "NCI",
              class:
                "w-full bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent"
            ) %>
          </div>

          <div class="flex flex-col">
            <%= label(form, :name, "Port name") %>
            <%= text_input(form, :name,
              class:
                "w-full bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent"
            ) %>
            <%= error_tag(form, :name) %>
          </div>

          <div class="flex flex-col mt-2">
            <%= label(form, :speed) %>
            <%= select(form, :speed, [115_200, 57600, 38400, 19200, 9600, 4800],
              class:
                "w-full bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent"
            ) %>
            <%= error_tag(form, :speed) %>
          </div>

          <div class="flex flex-col mt-2">
            <%= label(form, :data_bits) %>
            <%= select(form, :data_bits, [5, 6, 7, 8],
              selected: 8,
              class:
                "w-full bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent"
            ) %>
          </div>

          <div class="flex flex-col mt-2">
            <%= label(form, :parity) %>
            <%= select(form, :parity, [:none, :even, :odd, :space, :mark, :ignore],
              selected: :none,
              class:
                "w-full bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent"
            ) %>
          </div>

          <div class="flex flex-col mt-2">
            <%= label(form, :stop_bits) %>
            <%= select(form, :stop_bits, [1, 2],
              class:
                "w-full bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg block focus:ring-transparent focus:border-transparent"
            ) %>
          </div>
        </div>

        <%= submit("Update",
          class:
            "w-full h-11 px-10 mt-4 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center disabled:opacity-50",
          disabled: !@changeset.valid?,
          phx_disable_with: "Updating..."
        ) %>
      </.form>
    </div>
    """
  end

  def handle_event("validate", %{"form" => attrs}, socket) do
    socket
    |> assign(
      :changeset,
      CargoSettings.weight_sensor_changeset(attrs) |> Map.put(:action, :validate)
    )
    |> noreply()
  end

  def handle_event(
        "save",
        _,
        %{assigns: %{changeset: changeset, cargo_settings: cargo_settings}} = socket
      ) do
    params = changeset |> Ecto.Changeset.apply_action!(:update)
    {[name: name, type: type], opts} = params |> Enum.split_with(fn {k, _} -> k in [:name, :type] end)

    :ok = cargo_settings |> Map.put(:weight_sensor, params) |> AdminRoom.store_cargo_settings()

    send(self(), :update_cargo_settings)
    test_weight_sensor_connection(type, name, opts)

    socket
    |> noreply()
  end

  defp test_weight_sensor_connection(type, name, opts) do
    require Logger
    opts =
      if is_binary(opts[:parity]) do
        opts
        |> Keyword.delete(:parity)
        |> Keyword.put(:parity,  opts[:parity] |> String.to_existing_atom())
      else
        opts
      end
    send(self(), {:admin, {:connect_to_weight_sensor, {type, name}, opts}})

    {:admin, {:connect_to_weight_sensor, {type, name}, opts}}
    |> inspect()
    |> Logger.warn()

  end

  defp connection_status(assigns) do
    ~H"""
    <div class="flex flex-row">
      Connection:
      <div class={
        classes("ml-1", %{
          "text-gray-400" => @status == "Absent",
          "text-red-400" => @status == "Failed",
          "text-green-400" => @status == "Established"
        })
      }>
        <%= @status %>
      </div>
    </div>
    """
  end

  defp test_message(assigns) do
    ~H"""
    <div class="flex flex-row">
      <div class="ml-1">
        <%= @message %>
      </div>
    </div>
    """
  end
end
