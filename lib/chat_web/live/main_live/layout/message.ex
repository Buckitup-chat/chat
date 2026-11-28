defmodule ChatWeb.MainLive.Layout.Message do
  @moduledoc """
  Message layout
  Used both for rendering regular and exported messages.

  Message is passed under :msg attribute as either
  either %Chat.Dialogs.PrivateMessage{} (dialog message)
  or Chat.Rooms.PlainMessage{} (room message).

  Per-type bodies live in `Message.Body`, header parts in `Message.Header`,
  file and media parts in `Message.Media`, invite buttons in `Message.RoomInvite`.
  """
  use ChatWeb, :component

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Rooms.Room
  alias Chat.User
  alias ChatWeb.MainLive.Layout.Message.Body
  alias ChatWeb.MainLive.Layout.Message.Header
  alias ChatWeb.MainLive.Layout.Message.Media
  alias ChatWeb.MainLive.Layout.Message.RoomInvite
  alias Phoenix.LiveView.JS

  defdelegate text(assigns), to: Body
  defdelegate room_invite_navigation(assigns), to: RoomInvite
  defdelegate message_link(assigns), to: Header

  attr :author, Card, doc: "message author card"
  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :dynamic_attrs, :list, doc: "HTML attributes for the message block"
  attr :export?, :boolean, default: false, doc: "hide options and set path for exported file"
  attr :is_mine?, :boolean, doc: "is current user the author of the message?"
  attr :me, Identity, doc: "current user - used only for :dialog chat type"
  attr :msg, :map, required: true, doc: "message struct"
  attr :my_id, :string, doc: "current user's ID - used only for :room chat type"
  attr :peer, Card, doc: "the other user - used only for :dialog chat type"
  attr :room, Room, default: nil, doc: "room access was requested to"
  attr :room_keys, :map, default: [], doc: "the list of room keys"
  attr :linked, :boolean, default: false, doc: "link indicator"

  def message_block(assigns) do
    assigns =
      assigns
      |> assign_new(:is_mine?, fn
        %{chat_type: :dialog, msg: msg} ->
          msg.is_mine?

        %{chat_type: :room, msg: msg, my_id: my_id} ->
          msg.author_key == my_id
      end)
      |> assign_new(:author, fn
        %{chat_type: :dialog, is_mine?: is_mine?, me: me, peer: peer} ->
          (is_mine? && Card.from_identity(me)) || peer

        %{chat_type: :room, msg: msg, room: room} ->
          User.by_id(msg.author_key) ||
            (msg.author_key == room.pub_key && Card.new(room.name, room.pub_key)) ||
            Card.new("", msg.author_key)
      end)
      |> assign_new(:dynamic_attrs, fn
        %{export?: true} ->
          []

        %{chat_type: chat_type, export?: false, is_mine?: is_mine?, msg: msg} ->
          %{
            "phx-click" =>
              JS.dispatch("chat:select-message", detail: %{chatType: Atom.to_string(chat_type)}),
            "phx-value-id" => msg.id,
            "phx-value-index" => msg.index,
            "phx-value-is-mine" => Atom.to_string(is_mine?),
            "phx-value-type" => chat_type
          }
      end)
      |> assign_new(:linkable?, fn
        %{chat_type: :room, room: room} -> room.type == :public
        _ -> false
      end)
      |> Media.assign_file()

    ~H"""
    <div
      class="messageBlock flex flex-row px-2 sm:px-8"
      id={"message-block-#{@msg.id}"}
      data-type={@msg.type}
      {@dynamic_attrs}
    >
      <div
        class={"m-1 w-full flex " <> if(@is_mine?, do: "justify-end t-#{@chat_type}-mine-message x-mine", else: "justify-start x-peer")}
        id={"#{@chat_type}-message-#{@msg.id}"}
      >
        <Body.message
          author={@author}
          chat_type={@chat_type}
          color={if(@is_mine?, do: "bg-purple50", else: "bg-white")}
          export?={@export?}
          file={@file}
          is_mine?={@is_mine?}
          msg={@msg}
          receiver={assigns[:peer]}
          room={@room}
          room_keys={@room_keys}
          linked={@linked}
          linkable?={@linkable?}
        />
      </div>

      <%= unless @export? do %>
        <input
          onclick="event.stopPropagation(); event.preventDefault();"
          type="checkbox"
          class="selectCheckbox w-6 h-6 ml-3 mt-3 rounded-full text-purple/90 bg-black/10 border-gray-300 focus:ring-2 t-selectCheckbox"
        />
      <% end %>
    </div>
    """
  end
end
