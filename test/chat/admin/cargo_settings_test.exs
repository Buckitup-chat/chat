defmodule Chat.Admin.CargoSettingsTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Admin.CargoSettings

  describe "changeset/2" do
    @valid_params %{checkpoints: ["1234"]}

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
end
