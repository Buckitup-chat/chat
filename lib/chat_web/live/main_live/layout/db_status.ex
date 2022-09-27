defmodule ChatWeb.MainLive.Layout.DbStatus do
  @moduledoc "DB status layout"

  import ChatWeb.LiveHelpers, only: [icon: 1]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
      <button  class="sidebarIcon mb-1">
        <%= if @status.writable == :no do %>
          <!-- Red background on full button -->
          <span class="text-xs">Read Only</span>
        <% end %> 

        <%= if @status.mode == :internal do %> 
          <!-- Crossed DB icon -->
          <.icon id="sidebarChats" class="w-6 h-6"/>
        <% end %>
        <%= if @status.mode == :main do %> 
          <!-- DB icon -->
          <.icon id="sidebarRooms" class="w-6 h-6"/>
        <% end %>
        <%= if @status.mode == :internal_to_main do %> 
          <!-- Blinking or transparent DB icon -->
          <.icon id="admin" class="w-6 h-6"/>
        <% end %>
        <%= if @status.mode == :main_to_internal do %> 
          <!-- Blinking or transparent Crossed DB icon -->
          <.icon id="admin" class="w-6 h-6"/>
        <% end %>

        <span class="text-xs">
          <!-- Saving or downloading icon -->
          <%= if @status.flags[:backup] do %> backup <% end %>
          <!-- Syncronization icon, like cirle arrows -->
          <%= if @status.flags[:replication] do %> repl <% end %>
        </span>
      </button>
    """
  end
end
