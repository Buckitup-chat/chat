defmodule ChatWeb.MainLive.Layout.Message.Body do
  @moduledoc "Per-type message bodies of `ChatWeb.MainLive.Layout.Message.message_block/1`."
  use ChatWeb, :component

  require Logger

  import ChatWeb.MainLive.Layout.Message.Header, only: [header: 1, message_link: 1, timestamp: 1]

  import ChatWeb.MainLive.Layout.Message.Media,
    only: [audio: 1, file: 1, image: 1, media_file_info: 1]

  import ChatWeb.MainLive.Layout.Message.RoomInvite, only: [room_invite_navigation: 1]

  alias Chat.Card
  alias Chat.Content.RoomInvites
  alias Chat.Identity
  alias Chat.Rooms.Room
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Layout

  attr :msg, :map, required: true, doc: "message struct"

  def text(%{msg: %{type: :memo}} = assigns) do
    ~H"""
    <div class="px-4 w-full">
      <.vue v-component="LinkedText">
        <span class="flex-initial break-words">
          {nl2br(@msg.memo)}
        </span>
      </.vue>
    </div>
    """
  end

  def text(%{msg: %{type: :text}} = assigns) do
    ~H"""
    <div class="px-4 w-full">
      <.vue v-component="LinkedText">
        <span class="flex-initial break-words">
          {nl2br(@msg.content)}
        </span>
      </.vue>
    </div>
    """
  end

  attr :author, Card, required: true, doc: "message author card"
  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :color, :string, required: true, doc: "color class - either bg-purple50 or bg-white"
  attr :export?, :boolean, required: true, doc: "hide options and set path for exported file"
  attr :file, :map, required: true, doc: "file map"
  attr :is_mine?, :boolean, required: true, doc: "is current user the author of the message?"
  attr :msg, :map, required: true, doc: "message struct"
  attr :receiver, Card, doc: "peer in dialog"
  attr :room, Room, default: nil, doc: "room access was requested to"
  attr :room_keys, :map, doc: "the list of room keys"
  attr :linked, :boolean, default: false, doc: "link indicator"
  attr :linkable?, :boolean, default: false, doc: "linkable? Only for public rooms"

  def message(%{msg: %{type: :audio}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
      phx-hook="AudioFile"
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
        linkable?={@linkable?}
      />
      <div class="flex justify-end">
        <.message_link msg_index={@msg.index} msg_id={@msg.id} linked={@linked} />
        <.timestamp msg={@msg} />
      </div>
      <.audio export?={@export?} file={@file} msg={@msg} />
      <.media_file_info file={@file} />
    </div>
    """
  end

  def message(%{msg: %{type: :file}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
        linkable?={@linkable?}
      />
      <.file export?={@export?} file={@file} msg={@msg} />
      <div class="flex justify-end">
        <.message_link msg_index={@msg.index} msg_id={@msg.id} linked={@linked} />
        <.timestamp msg={@msg} />
      </div>
    </div>
    """
  end

  def message(%{msg: %{type: :image}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
        linkable?={@linkable?}
      />
      <div class="flex justify-end">
        <.message_link msg_index={@msg.index} msg_id={@msg.id} linked={@linked} />
        <.timestamp msg={@msg} />
      </div>
      <.image chat_type={@chat_type} msg={@msg} export?={@export?} file={@file} />
      <.media_file_info file={@file} />
    </div>
    """
  end

  def message(%{msg: %{type: type}} = assigns) when type in [:memo, :text] do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xs sm:max-w-md min-w-[180px] t-chat-mine-message rounded-lg shadow-lg"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
        linkable?={@linkable?}
      />
      <span class="x-content"><.text msg={@msg} /></span>
      <div class="flex justify-end">
        <.message_link msg_index={@msg.index} msg_id={@msg.id} linked={@linked} />
        <.timestamp msg={@msg} />
      </div>
    </div>
    """
  end

  def message(%{msg: %{type: :request}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}
    >
      <div class="py-1 px-2">
        <Layout.Card.hashed_name card={@author} style_spec={:room_request_message} show_link?={true} />
        <p class="inline-flex">requested access to room</p>
        <Layout.Card.hashed_name room={@room} style_spec={:room_request_message} show_link?={true} />
      </div>
      <.timestamp msg={@msg} />
    </div>
    """
  end

  def message(%{msg: %{type: :room_invite}} = assigns) do
    # TODO: put in Chat.Messaging
    assigns =
      assigns
      |> assign_new(:room_card, fn
        %{msg: %{content: json}} ->
          json
          |> StorageId.from_json()
          |> RoomInvites.get()
          |> Identity.from_strings()
          |> Card.from_identity()
      end)

    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}
    >
      <div class="py-1 px-2">
        <%= if @is_mine? do %>
          <%= if @receiver == @author do %>
            <p class="inline-flex">You got the key copy of the room</p>
          <% else %>
            <Layout.Card.hashed_name card={@receiver} style_spec={:room_invite} show_link?={true} />
            <p class="inline-flex">is invited by you into</p>
          <% end %>
        <% else %>
          <Layout.Card.hashed_name card={@author} style_spec={:room_invite} show_link?={true} />
          <p class="inline-flex">wants you to join the room</p>
        <% end %>
        <Layout.Card.hashed_name room={@room_card} style_spec={:room_invite} />
      </div>

      <%= unless @export? do %>
        <%= if (@is_mine? and @author == @receiver) or not @is_mine? do %>
          <div
            data-room={Enigma.short_hash(@room_card)}
            class="x-invite-navigation flex flex-col sm:flex-row sm:items-center sm:justify-between px-2 my-1"
          >
            <.room_invite_navigation room_key={@room_card.pub_key} room_keys={@room_keys} msg={@msg} />
          </div>
        <% end %>
      <% end %>

      <.timestamp msg={@msg} />
    </div>
    """
  rescue
    _ -> ~H""
  end

  def message(%{msg: %{type: :video}} = assigns) do
    ~H"""
    <div
      id={"message-#{@msg.id}"}
      class={"#{@color} max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}
    >
      <.header
        author={@author}
        chat_type={@chat_type}
        export?={@export?}
        file={@file}
        is_mine?={@is_mine?}
        msg={@msg}
        linkable?={@linkable?}
      />
      <.message_link msg_index={@msg.index} msg_id={@msg.id} linked={@linked} />
      <.timestamp msg={@msg} />
      <video src={@file[:url]} class="a-video" controls />
      <.media_file_info file={@file} />
    </div>
    """
  end

  def message(assigns) do
    ["[message] ", "error rendering ", inspect(assigns[:msg], pretty: true)] |> Logger.warning()

    ~H"""
    <!-- error rendering message -->
    """
  end

  defp nl2br(str), do: Utils.trim_text(str) |> Enum.intersperse(tag(:br))
end
