defmodule ChatWeb.MainLive.Layout.Popup do
  @moduledoc "Modal components"
  use ChatWeb, :component
  import ChatWeb.LiveHelpers, only: [modal: 1, hide_modal: 1, icon: 1]

  :to_do_modals_refactoring

  attr :id, :string, default: "restrict-write-actions"

  def restrict_write_actions(assigns) do
    ~H"""
    <.modal id={@id} class="">
      <h1 class="text-base font-bold text-grayscale">Read only mode</h1>
      <div class="mt-3 w-full h-7 flex items-center justify-between">
        <.icon id="alert" class="ml-1 w-10 h-10  fill-black/40" />
        <blockquote class="ml-2 text-sm text-black/50 mr-3">
          The device switched into read only mode. Storage drive needs to be upgraded.
        </blockquote>
      </div>
      <button
        phx-click={hide_modal(@id)}
        class="w-full mt-5 mr-1 h-12 bg-grayscale text-white rounded-lg"
      >
        Ok
      </button>
    </.modal>
    """
  end
end
