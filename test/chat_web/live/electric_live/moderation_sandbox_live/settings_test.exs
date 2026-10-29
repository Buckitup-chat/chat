defmodule ChatWeb.ElectricLive.ModerationSandboxLive.SettingsTest do
  @moduledoc "Settings handle_event unit tests."
  use ExUnit.Case, async: true

  alias ChatWeb.ElectricLive.ModerationSandboxLive.Settings

  defp socket(overrides \\ %{}) do
    defaults = %{
      identity: %{origin_hash: "oh", sign_skey: "sk"},
      origin_settings: [],
      setting_form_key: "review_access",
      setting_form_value: "open",
      setting_form_open: false,
      error_message: nil,
      request_log: []
    }

    assigns = Map.merge(defaults, overrides)
    %Phoenix.LiveView.Socket{assigns: Map.merge(%Phoenix.LiveView.Socket{}.assigns, assigns)}
  end

  describe "setting_form_change" do
    test "sets setting_form_open to true" do
      {:noreply, result} =
        Settings.handle_event(
          "setting_form_change",
          %{"key" => "review_access"},
          socket(),
          "http://localhost",
          %{}
        )

      assert result.assigns.setting_form_open == true
    end

    test "switching key resets value to current setting value" do
      existing_settings = [
        %{key: "auth_token", value: "secret123", deleted_flag: false}
      ]

      {:noreply, result} =
        Settings.handle_event(
          "setting_form_change",
          %{"key" => "auth_token"},
          socket(%{origin_settings: existing_settings, setting_form_key: "review_access"}),
          "http://localhost",
          %{}
        )

      assert result.assigns.setting_form_key == "auth_token"
      assert result.assigns.setting_form_value == "secret123"
    end

    test "switching key prefills default when no existing value" do
      {:noreply, result} =
        Settings.handle_event(
          "setting_form_change",
          %{"key" => "review_token_ttl_days"},
          socket(%{setting_form_key: "review_access"}),
          "http://localhost",
          %{}
        )

      assert result.assigns.setting_form_key == "review_token_ttl_days"
      assert result.assigns.setting_form_value == "7"
    end

    test "typing in same key preserves typed value" do
      {:noreply, result} =
        Settings.handle_event(
          "setting_form_change",
          %{"key" => "review_access", "value" => "invite_only"},
          socket(%{setting_form_key: "review_access"}),
          "http://localhost",
          %{}
        )

      assert result.assigns.setting_form_key == "review_access"
      assert result.assigns.setting_form_value == "invite_only"
    end
  end
end
