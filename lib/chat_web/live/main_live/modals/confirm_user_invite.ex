defmodule ChatWeb.MainLive.Modals.ConfirmUserInvite do
  @moduledoc "Confirm user invitation to the room"
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Layout

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-base font-bold text-grayscale">Invite new one</h1>
      <div class="mt-1 w-full h-7 flex items-center justify-between">
        <blockquote class="mt-2 ml-2 text-sm text-black/50 mr-3 break-normal">
          Are you sure you want to invite
          <span><Layout.Card.hashed_name card={@user} style_spec={:room_invite} /></span>
          to the admin room?
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
          phx-click="admin/confirm-user-invite"
          phx-value-hash={@user.hash}
          class="confirmButton w-full mt-5 mr-1 h-12 bg-grayscale text-white rounded-lg"
        >
          Ok
        </button>
      </div>
    </div>
    """
  end
end
