defmodule Chat.Admin.CargoSettingsTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Admin.CargoSettings
  alias Chat.Card

  describe "checkpoints_changeset/2" do
    @valid_params %{checkpoints: [%Card{}, %Card{}]}

    test "with valid params returns valid changeset" do
      assert %Ecto.Changeset{} =
               changeset = CargoSettings.checkpoints_changeset(%CargoSettings{}, @valid_params)

      assert changeset.valid?
    end

    test "with missing checkpoints returns an error" do
      params = @valid_params |> Map.put(:checkpoints, nil)
      changeset = CargoSettings.checkpoints_changeset(%CargoSettings{}, params)
      assert_has_error(changeset, :checkpoints, "can't be blank")
    end
  end

  describe "camera_sensors_changeset/2" do
    @valid_params %{camera_sensors: ["url1", "url2", "url3"]}

    test "with valid params returns valid changeset" do
      assert %Ecto.Changeset{} =
               changeset = CargoSettings.camera_sensors_changeset(%CargoSettings{}, @valid_params)

      assert changeset.valid?
    end

    test "with empty urls returns error" do
      assert %Ecto.Changeset{} =
               changeset =
               CargoSettings.camera_sensors_changeset(%CargoSettings{}, %{
                 camera_sensors: ["", "", ""]
               })

      assert !changeset.valid?
    end

    test "reset changeset is valid" do
      assert %Ecto.Changeset{} =
               changeset =
               CargoSettings.camera_sensors_changeset(%CargoSettings{
                 camera_sensors: @valid_params[:camera_sensors]
               })

      assert %Ecto.Changeset{} = reset_changeset = CargoSettings.reset_camera_sensors(changeset)

      assert reset_changeset.valid?
    end
  end

  describe "weight_sensor_changeset/1" do
    @valid_params %{name: "ttyAMA0", speed: 115_200, data_bits: 8, stop_bits: 1, parity: "none", type: "NCI"}

    test "with valid params returns valid changeset" do
      assert %Ecto.Changeset{} = changeset = CargoSettings.weight_sensor_changeset(@valid_params)

      assert changeset.valid?
    end

    test "with missing attrs returns an error" do
      assert %Ecto.Changeset{} = changeset = CargoSettings.weight_sensor_changeset(%{})

      assert !changeset.valid?
    end
  end
end
