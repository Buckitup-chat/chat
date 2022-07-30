defmodule ChatWeb.MainLive.Layout.Admin do
  @moduledoc "Admin room related layout"
  use Phoenix.Component

  def container(assigns) do
    ~H"""
      <div class="flex flex-col">
        <%= render_slot(@inner_block) %> 
      </div>
    """
  end

  def row(assigns) do
    ~H"""
      <div class="flex flex-row flex-wrap m-2">
        <%= render_slot(@inner_block) %> 
      </div>
    """
  end

  def block(assigns) do
    ~H"""
      <article class="m-4 w-50 p-4 rounded-xl bg-gray-200">
        <header class="text-2xl bg-white/50 rounded-md p-2"><%= @title %></header>
        <%= render_slot(@inner_block) %> 
      </article>
    """
  end
end
