defmodule ChatWeb.MainLive.Layout.DbStatus do
  @moduledoc "DB status layout"

  import ChatWeb.LiveHelpers, only: [icon: 1]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
      <button  class="sidebarIcon mb-1">
        <%= if @status.writable == :no do %>
          <!-- Red background on full button -->
            <div class="ml-6 mb-2">
              <.icon id="redDataBase" class="w-6 h-6"/>
            </div>
        <% end %>

        <%= if @status.mode == :internal do %>
          <!-- DB icon -->
            <div class="ml-[23.5px] mb-2">
              <.icon id="dataBase" class="w-6 h-6"/>
            </div>
        <% end %>
        <%= if @status.mode == :main do %>
          <!-- Crossed DB icon -->
            <div class="ml-5 mb-2">
              <.icon id="crossedDataBase" class="w-6 h-6 animation-pulse"/>
            </div>
        <% end %>
        <%= if @status.mode == :internal_to_main do %>
          <!-- Blinking or transparent DB icon -->
            <div class="ml-5 mb-2">
              <.icon id="dataBase" class="w-6 h-6 animation-pulse"/>
            </div>
        <% end %>
        <%= if @status.mode == :main_to_internal do %>
          <!-- Blinking or transparent Crossed DB icon -->
            <div class="ml-5 mb-2">
              <.icon id="crossedDataBase" class="w-6 h-6 animation-pulse"/>
            </div>
        <% end %>


          <!-- Saving or downloading icon -->
          <%= if @status.flags[:backup] do %>
          <div class="ml-[28px] mb-1">
            <.icon id="backUp" class="w-6 h-6"/>
          </div>
          <% end %>
          <!-- Syncronization icon, like cirle arrows -->
          <%= if @status.flags[:replication] do %>
          <div class="ml-[28px]">
            <.icon id="replication" class="w-6 h-6"/>
          </div>
           <% end %>
         <!--  <div class="ml-7">
              <.icon id="car" class="w-6 h-6"/>
            </div> -->
      </button>
    """
  end
end
