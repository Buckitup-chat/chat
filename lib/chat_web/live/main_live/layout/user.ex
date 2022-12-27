defmodule ChatWeb.MainLive.Layout.User do
  @moduledoc false
  use ChatWeb, :component

  alias Chat.Card
  alias Chat.Utils

  attr :user, Card, required: true
  attr :hash_style, :string, default: "text-sm tracking-tighter text-grayscale600"
  attr :name_style, :string, default: "text-sm"

  def username(assigns) do
    ~H"""
    <div class="inline-flex">
      <tt class={"#{@hash_style}"}>[<%= Utils.short_hash(@user.hash) %>]</tt>
      <div class={"ml-1 #{@name_style}"}><%= @user.name %></div>
    </div>
    """
  end
end
