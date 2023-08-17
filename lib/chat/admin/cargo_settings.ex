defmodule Chat.Admin.CargoSettings do
  @moduledoc """
  Defines cargo settings form data structure and handles validation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @camera_sensors_default [""]
  @primary_key false
  embedded_schema do
    field(:checkpoints, {:array, :string}, default: [])
    field(:camera_sensors, {:array, :string}, default: @camera_sensors_default)
    field(:weight_sensor, :map, default: %{type: "NCI", parity: :none})
  end

  def checkpoints_changeset(%__MODULE__{} = settings, attrs \\ %{}) do
    settings
    |> cast(attrs, [:checkpoints])
    |> validate_required([:checkpoints])
  end

  def camera_sensors_changeset(%__MODULE__{} = settings, attrs \\ %{}) do
    settings
    |> cast(attrs, [:camera_sensors], empty_values: [])
    |> validate_required([:camera_sensors])
    |> validate_change(:camera_sensors, fn :camera_sensors, sensors ->
      cond do
        sensors == [""] ->
          []

        Enum.any?(sensors, fn url -> String.trim(url) == "" end) ->
          [camera_sensors: "fill in all sensors for storing"]

        true ->
          []
      end
    end)
  end

  def camera_sensors_field(%Ecto.Changeset{} = changeset) do
    changeset |> get_field(:camera_sensors, @camera_sensors_default)
  end

  def reset_camera_sensors(%Ecto.Changeset{} = changeset) do
    changeset |> put_change(:camera_sensors, @camera_sensors_default)
  end

  @weight_sensor_schema %{
    type: :string,
    name: :string,
    speed: :integer,
    data_bits: :integer,
    parity: :string,
    stop_bits: :integer
  }
  def weight_sensor_changeset(attrs \\ %{}) do
    {%{}, @weight_sensor_schema}
    |> cast(attrs, Map.keys(@weight_sensor_schema))
    |> validate_required(Map.keys(@weight_sensor_schema))
  end
end
