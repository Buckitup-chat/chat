defmodule ChatWeb.MainLive.Layout.Card do
  @moduledoc false
  use ChatWeb, :component

  alias Chat.Card
  alias Chat.Rooms.Room
  alias Chat.Utils

  @basic_text_style "text-sm"
  @grayscale_text_style "text-sm tracking-tighter text-grayscale600"
  @white_hash_text_style "text-base text-white/60"
  @white_name_text_style "text-base font-bolt text-white t-peer-name"
  @purple_text_style "font-bold text-sm text-purple"

  attr :card, Card, doc: "room/user card"
  attr :room, Room, doc: "room sctruct"
  attr :me, Identity, doc: "current user"
  attr :is_me?, :boolean, doc: "is this the current user's card?"
  attr :stylized_as, :atom, default: :chat_list

  def details(assigns) do
    assigns =
      assigns
      |> assign_new(:card, fn
        %{card: %Card{} = card} -> card
        %{room: %Room{} = room} -> Card.new(room.name, room.pub_key)
        %{room: %{hash: _, name: name, pub_key: pub_key}} -> Card.new(name, pub_key)
      end)
      |> assign_new(:is_me?, fn
        %{card: card, me: me} -> Card.from_identity(me) == card
        _ -> false
      end)
      |> assign_new(:hash_style, fn
        %{stylized_as: :chat_list} -> @grayscale_text_style
        %{stylized_as: :chat_header} -> @white_hash_text_style
        %{stylized_as: :room_invite} -> @purple_text_style
        %{stylized_as: :room_request_list} -> @purple_text_style
        %{stylized_as: :room_request_message} -> @grayscale_text_style
        %{stylized_as: :message_header} -> @grayscale_text_style
      end)
      |> assign_new(:name_style, fn
        %{stylized_as: :chat_list} -> @basic_text_style
        %{stylized_as: :chat_header} -> @white_name_text_style
        %{stylized_as: :room_invite} -> @purple_text_style
        %{stylized_as: :room_request_list} -> @purple_text_style
        %{stylized_as: :room_request_message} -> @basic_text_style
        %{stylized_as: :message_header} -> @purple_text_style
      end)

    ~H"""
    <div class="inline-flex">
      <%= if @is_me? do %>
        <div class="text-sm">My notes</div>
      <% else %>
        <tt class={"#{@hash_style}"}>[<%= Utils.short_hash(@card.hash) %>]</tt>
        <div class={"ml-1 #{@name_style}"}><%= @card.name %></div>
      <% end %>
    </div>
    """
  end
end
