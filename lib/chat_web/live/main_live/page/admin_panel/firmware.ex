defmodule ChatWeb.MainLive.Page.AdminPanel.Firmware do
  @moduledoc """
  Firmware upgrades in the admin panel: the confirmation modals, starting an upgrade
  from an uploaded file or a GitHub release, and relaying the platform's progress to
  the upgrade forms.

  Part of the `ChatWeb.MainLive.Page.AdminPanel` namespace.
  """

  import Phoenix.LiveView, only: [put_flash: 3, send_update: 2]
  import ChatWeb.LiveHelpers, only: [open_modal: 2, open_modal: 3, close_modal: 1]

  alias ChatWeb.MainLive.Admin.FirmwareUpgradeForm
  alias ChatWeb.MainLive.Admin.GithubFirmwareUpgradeForm

  def upgrade_firmware_confirmation(socket) do
    socket
    |> open_modal(ChatWeb.MainLive.Modals.ConfirmFirmwareUpgrade)
  end

  def upgrade_firmware(socket) do
    send_update(FirmwareUpgradeForm, id: :firmware_upgrade_form, step: :upgrade)

    socket
    |> close_modal()
  end

  def notify_firmware_upgraded(socket) do
    send_update(FirmwareUpgradeForm, id: :firmware_upgrade_form, substep: :done)

    socket
    |> put_flash(:info, "Firmware upgraded")
  end

  def github_upgrade_firmware_confirmation(socket, release) do
    socket
    |> open_modal(ChatWeb.MainLive.Modals.ConfirmGithubFirmwareUpgrade, %{release: release})
  end

  def github_upgrade_firmware(socket) do
    send_update(GithubFirmwareUpgradeForm,
      id: :github_firmware_upgrade_form,
      action: :start_download
    )

    socket
    |> close_modal()
  end

  def github_firmware_upgrade_response(socket, message) do
    send_update(GithubFirmwareUpgradeForm,
      id: :github_firmware_upgrade_form,
      platform_response: message
    )

    socket
  end
end
