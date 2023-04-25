defmodule Chat.Admin.MediaSettingsTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Admin.MediaSettings

  describe "changeset/2" do
    @valid_params %{
      functionality: "backup"
    }

    test "has backup as the default option" do
      assert %Ecto.Changeset{} = changeset = MediaSettings.changeset(%MediaSettings{}, %{})

      assert changeset.valid?

      assert %MediaSettings{} = media_settings = Ecto.Changeset.apply_changes(changeset)
      assert media_settings.functionality == :backup
    end

    test "with valid params returns valid changeset" do
      assert %Ecto.Changeset{} =
               changeset = MediaSettings.changeset(%MediaSettings{}, @valid_params)

      assert changeset.valid?
    end

    test "with missing or invalid functionality returns an error" do
      params = @valid_params |> Map.put(:functionality, nil)
      changeset = MediaSettings.changeset(%MediaSettings{}, params)
      assert_has_error(changeset, :functionality, "can't be blank")

      params = @valid_params |> Map.put(:functionality, "unknown")
      changeset = MediaSettings.changeset(%MediaSettings{}, params)
      assert_has_error(changeset, :functionality, "is invalid")
    end
  end
end
