defmodule ChatWeb.MainLive.Modals.ConfirmFirmwareUpgrade do
  @moduledoc "Upgrade firmware confirmation"
  use ChatWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-base font-bold text-grayscale">Upgrade firmware?</h1>
      <div class="mt-1 w-full h-7 flex items-center justify-between">
        <blockquote class="mt-2 ml-2 text-sm text-black/50 mr-3">
          Are you sure?. The reb  oot will be performed automatically after the upgrade.
        </blockquote>
      </div>
      <div class="mt-1 flex items-center justify-between">
        <button
          phx-click="modal:close"
          class="w-full mt-5 mr-1 h-12 bg-grayscale text-white rounded-lg"
        >
          Cancel
        </button>
        <button
          phx-click="admin/upgrade-firmware"
          class="confirmButton w-full mt-5 mr-1 h-12 bg-grayscale text-white rounded-lg"
        >
          Ok
        </button>
      </div>
    </div>
    """
  end
end
