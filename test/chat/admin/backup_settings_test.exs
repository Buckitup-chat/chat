defmodule Chat.Admin.BackupSettingsTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Admin.BackupSettings

  describe "changeset/2" do
    @valid_params %{
      type: "regular"
    }

    test "has regular as the default option" do
      assert %Ecto.Changeset{} = changeset = BackupSettings.changeset(%BackupSettings{}, %{})

      assert changeset.valid?

      assert %BackupSettings{} = backup_settings = Ecto.Changeset.apply_changes(changeset)
      assert backup_settings.type == :regular
    end

    test "with valid params returns valid changeset" do
      assert %Ecto.Changeset{} =
               changeset = BackupSettings.changeset(%BackupSettings{}, @valid_params)

      assert changeset.valid?
    end

    test "with missing or invalid type returns an error" do
      params = @valid_params |> Map.put(:type, nil)
      changeset = BackupSettings.changeset(%BackupSettings{}, params)
      assert_has_error(changeset, :type, "can't be blank")

      params = @valid_params |> Map.put(:type, "unknown")
      changeset = BackupSettings.changeset(%BackupSettings{}, params)
      assert_has_error(changeset, :type, "is invalid")
    end
  end
end
