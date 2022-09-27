defmodule ChatWeb.MainLive.Layout.DbStatus do
  @moduledoc "DB status layout"

  import ChatWeb.LiveHelpers, only: [icon: 1]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
      <button  class="sidebarIcon mb-1">
        <%= if @status.writable == :no do %>
          <span class="text-xs">Read Only</span>
        <% end %> 

        <%= if @status.mode == :internal do %> 
          <.icon id="sidebarChats" class="w-6 h-6"/>
        <% end %>
        <%= if @status.mode == :main do %> 
          <.icon id="sidebarRooms" class="w-6 h-6"/>
        <% end %>
        <%= if @status.mode == :internal_to_main do %> 
          <.icon id="admin" class="w-6 h-6"/>
        <% end %>
        <%= if @status.mode == :main_to_internal do %> 
          <.icon id="admin" class="w-6 h-6"/>
        <% end %>

        <span class="text-xs">
          <%= if @status.flags[:backup] do %> backup <% end %>
          <%= if @status.flags[:replication] do %> repl <% end %>
        </span>
      </button>
    """
  end
end
