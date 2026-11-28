defmodule ChatWeb.MainLive.Layout.Message.RoomInvite do
  @moduledoc "Accept / open buttons under a room invite message."
  use ChatWeb, :component

  attr :room_key, :string, required: true, doc: "room public key"
  attr :room_keys, :list, required: true, doc: "room_map keys"
  attr :msg, :map, required: true, doc: "message struct"

  def room_invite_navigation(assigns) do
    ~H"""
    <%= if @room_key in @room_keys do %>
      <button
        class="w-full h-12 border-0 rounded-lg bg-grayscale text-white"
        phx-click="dialog/message/accept-room-invite-and-open-room"
        phx-value-id={@msg.id}
        phx-value-index={@msg.index}
      >
        Go to Room
      </button>
    <% else %>
      <button
        class="acceptInviteButton w-full sm:w-[30%] h-12 border-0 rounded-lg bg-grayscale text-white mb-2 sm:mb-0 sm:mr-2"
        phx-click="dialog/message/accept-room-invite"
        phx-value-id={@msg.id}
        phx-value-index={@msg.index}
      >
        Accept
      </button>
      <button
        class="w-full sm:w-[40%] h-12 border-0 rounded-lg bg-grayscale text-white mb-2 sm:mb-0 sm:mr-2"
        phx-click="dialog/message/accept-room-invite-and-open-room"
        phx-value-id={@msg.id}
        phx-value-index={@msg.index}
      >
        Accept and Open
      </button>
      <button
        class="w-full sm:w-[30%] h-12 border-0 rounded-lg bg-grayscale text-white mb-2 sm:mb-0 sm:mr-2"
        phx-click="dialog/message/accept-all-room-invites"
      >
        Accept all
      </button>
    <% end %>
    """
  end
end
