defmodule ChatWeb.MainLive.Layout.Card do
  @moduledoc "Card rendering component"

  use ChatWeb, :component

  alias Chat.Card
  alias Chat.Rooms.Room
  alias Chat.Utils

  @basic_text_style "text-sm"
  @grayscale_text_style "text-sm tracking-tighter text-grayscale600"
  @white_hash_text_style "text-base text-white/60"
  @white_name_text_style "text-base font-bolt text-white t-peer-name"
  @purple_text_style "text-sm text-purple"
  @purple_bold_text_style "font-bold text-sm text-purple"

  @style_config %{
    dialog_selection: %{hash: @grayscale_text_style, name: @basic_text_style},
    chat_header: %{hash: @white_hash_text_style, name: @white_name_text_style},
    room_invite: %{hash: @purple_bold_text_style, name: @purple_bold_text_style},
    room_request_list: %{hash: @purple_bold_text_style, name: @purple_bold_text_style},
    room_request_message: %{hash: @grayscale_text_style, name: @basic_text_style},
    message_header: %{hash: @grayscale_text_style, name: @purple_bold_text_style},
    room_selection: %{hash: @grayscale_text_style, name: @basic_text_style}
  }

  attr :card, Card, doc: "room/user card"
  attr :me, Identity, doc: "current user"
  attr :is_me?, :boolean, doc: "is this the current user's card?"
  attr :room, Room, doc: "room sctruct"
  attr :selected_room, Room, doc: "selected room sctruct"
  attr :style_spec, :atom, default: :dialog_selection, doc: "style spec"

  def hashed_name(assigns) do
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
      |> assign_new(:hash_style, fn %{style_spec: spec} -> @style_config[spec][:hash] end)
      |> assign_new(:name_style, &set_name_style/1)

    ~H"""
    <div class="inline-flex">
      <%= if @is_me? do %>
        <div class="text-sm t-my-notes">My notes</div>
      <% else %>
        <tt class={"#{@hash_style}"}>[<%= Utils.short_hash(@card.hash) %>]</tt>
        <div class={"ml-1 #{@name_style}"}><%= @card.name %></div>
      <% end %>
    </div>
    """
  end

  defp set_name_style(%{style_spec: :room_selection, room: room, selected_room: selected_room}) do
    if selected_room && room.pub_key == selected_room.pub_key do
      @purple_text_style
    else
      @style_config[:room_selection][:name]
    end
  end

  defp set_name_style(%{style_spec: spec}), do: @style_config[spec][:name]
end
