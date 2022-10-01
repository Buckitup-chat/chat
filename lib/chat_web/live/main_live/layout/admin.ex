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

  def db_status(assigns) do
    flags =
      assigns.status.flags
      |> Enum.filter(fn {_, v} -> v == true end)
      |> Enum.map_join(", ", &elem(&1, 0))

     budget =
      assigns.status.write_budget
      |> Integer.digits(1000)
      |> Enum.map_join(" ", &to_string/1)

    assigns = assign(assigns, flags: flags, budget: budget)

    ~H"""
      <label class="text-black/50"> Mode: </label><span><%= @status.mode %></span><br/>
      <label class="text-black/50"> Flags: </label><span><%= @flags %></span><br/>
      <label class="text-black/50"> Writable: </label><span><%= @status.writable %></span><br/>
      <label class="text-black/50"> Write Budget: </label><span><%= @budget %> bytes</span><br/>
    """
  end
end
