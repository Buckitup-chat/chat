defmodule ChatWebTest.MainLive.Admin.CargoWeightSensorFormTest do
  # Cargo settings live in the global AdminDb
  use ChatWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  alias Chat.Admin.CargoSettings
  alias Chat.AdminRoom
  alias ChatWeb.MainLive.Admin.CargoWeightSensorForm

  @valid %{
    "type" => "Balena D700",
    "name" => "ttyUSB0",
    "speed" => "9600",
    "data_bits" => "8",
    "parity" => "even",
    "stop_bits" => "1"
  }

  setup do
    original = AdminRoom.get_cargo_settings()
    :ok = AdminRoom.store_cargo_settings(%CargoSettings{})
    on_exit(fn -> AdminRoom.store_cargo_settings(original) end)
  end

  test "default settings render the form without connecting" do
    view = mount_form()

    assert has_element?(view, "div", "Absent")
    assert has_element?(view, "select[name='form[type]']")
    refute_handle_info(view, {:admin, {:connect_to_weight_sensor, _, _}}, 100)
  end

  test "stored sensor is connected on mount with atom parity" do
    store_weight_sensor(%{type: "NCI", name: "ttyS0", speed: 115_200, parity: "odd"})

    view = mount_form()

    assert_handle_info(
      view,
      {:admin, {:connect_to_weight_sensor, {"NCI", "ttyS0"}, opts}}
    )

    assert opts[:parity] == :odd
    assert opts[:speed] == 115_200
  end

  test "stored sensor keeps an atom parity as is" do
    store_weight_sensor(%{type: "NCI", name: "ttyS0", parity: :none})

    view = mount_form()

    assert_handle_info(
      view,
      {:admin, {:connect_to_weight_sensor, {"NCI", "ttyS0"}, [parity: :none]}}
    )
  end

  test "validate toggles the submit button and shows errors" do
    view = mount_form()

    view |> form("form", form: Map.put(@valid, "name", "")) |> render_change()
    assert has_element?(view, "button[type=submit][disabled]")
    assert has_element?(view, "span.invalid-feedback[phx-feedback-for='form[name]']", "blank")

    view |> form("form", form: @valid) |> render_change()
    refute has_element?(view, "button[type=submit][disabled]")
  end

  test "save stores the sensor, notifies the panel and connects to it" do
    view = mount_form()

    view |> form("form", form: @valid) |> render_change()
    view |> form("form") |> render_submit()

    assert_handle_info(view, :update_cargo_settings)

    assert_handle_info(
      view,
      {:admin, {:connect_to_weight_sensor, {"Balena D700", "ttyUSB0"}, opts}}
    )

    assert Enum.sort(opts) == [data_bits: 8, parity: :even, speed: 9600, stop_bits: 1]

    assert %{type: "Balena D700", name: "ttyUSB0", parity: "even"} =
             AdminRoom.get_cargo_settings().weight_sensor
  end

  # Helpers

  defp mount_form do
    {:ok, view, _} =
      live_isolated_component(CargoWeightSensorForm, assigns: %{id: :cargo_weight_sensor_form})

    view
  end

  defp store_weight_sensor(sensor) do
    :ok = AdminRoom.store_cargo_settings(%CargoSettings{weight_sensor: sensor})
  end
end
