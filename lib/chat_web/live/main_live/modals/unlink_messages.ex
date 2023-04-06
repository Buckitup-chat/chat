defmodule ChatWeb.MainLive.Modals.UnlinkMessages do
  @moduledoc "Unlink messages confirmation"
  use ChatWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-base font-bold text-grayscale">Unlink messages?</h1>
      <div class="mt-1 w-full h-7 flex items-center justify-between">
        <blockquote class="ml-2 text-sm text-black/50 mr-3">
          All message links in the room will be canceled.
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
          phx-click="room/unlink-messages"
          class="w-full mt-5 mr-1 h-12 bg-grayscale text-white rounded-lg"
        >
          Ok
        </button>
      </div>
    </div>
    """
  end
end
