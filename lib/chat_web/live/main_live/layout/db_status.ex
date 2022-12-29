defmodule ChatWeb.MainLive.Layout.DbStatus do
  @moduledoc "DB status layout"

  import ChatWeb.LiveHelpers

  use Phoenix.Component

  def desktop(assigns) do
    ~H"""
    <div class="sidebarIcon mb-1">
      <%= if @status.mode == :internal do %>
        <!-- Crossed DB icon -->
        <div class="pb-2.5 pl-1.5">
          <.icon
            id="crossedDataBase"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.mode == :main do %>
        <!-- DB icon -->
        <div class="pb-2.5 pl-1">
          <.icon
            id="dataBase"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.mode == :internal_to_main do %>
        <!-- Blinking or transparent DB icon -->
        <div class="pb-2.5 pl-1.5">
          <.icon
            id="dataBase"
            class={
              classes("w-6 h-6 fill-gray-500 animate-pulse", %{
                "fill-red-600" => @status.writable == :no
              })
            }
          />
        </div>
      <% end %>
      <%= if @status.mode == :main_to_internal do %>
        <!-- Blinking or transparent Crossed DB icon -->
        <div class="pb-2.5 pl-1.5">
          <.icon
            id="crossedDataBase"
            class={
              classes("w-6 h-6 fill-gray-500 animate-pulse", %{
                "fill-red-600" => @status.writable == :no
              })
            }
          />
        </div>
      <% end %>
      <!-- Saving or downloading icon -->
      <%= if @status.flags[:backup] do %>
        <div class="pb-1 pl-3">
          <.icon
            id="backUp"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <!-- Syncronization icon, like cirle arrows -->
      <%= if @status.flags[:replication] do %>
        <div class="pl-3">
          <.icon
            id="replication"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <!-- <div class="pl-2">
              <.icon id="car" class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}/>
            </div>-->
    </div>
    """
  end

  def mobile(assigns) do
    ~H"""
    <div class="flex flex-row items-center pt-2 w-[63%] justify-end">
      <%= if @status.mode == :internal do %>
        <!-- Crossed DB icon -->
        <div class="pb-2 pr-1">
          <.icon
            id="crossedDataBase"
            class={
              classes("w-5 h-[19.5px] fill-gray-200", %{"fill-red-600" => @status.writable == :no})
            }
          />
        </div>
      <% end %>
      <%= if @status.mode == :main do %>
        <!-- DB icon -->
        <div class="pb-2 pr-1">
          <.icon
            id="dataBase"
            class={
              classes("w-5 h-[19.5px] fill-gray-200", %{"fill-red-600" => @status.writable == :no})
            }
          />
        </div>
      <% end %>
      <%= if @status.mode == :internal_to_main do %>
        <!-- Blinking or transparent DB icon -->
        <div class="pb-2 pr-1">
          <.icon
            id="dataBase"
            class={
              classes("w-5 h-[19.5px] fill-gray-300 animate-pulse", %{
                "fill-red-600" => @status.writable == :no
              })
            }
          />
        </div>
      <% end %>
      <%= if @status.mode == :main_to_internal do %>
        <!-- Blinking or transparent Crossed DB icon -->
        <div class="pb-2 pr-1">
          <.icon
            id="crossedDataBase"
            class={
              classes("w-5 h-[19.5px] fill-gray-300 animate-pulse", %{
                "fill-red-600" => @status.writable == :no
              })
            }
          />
        </div>
      <% end %>
      <!-- Saving or downloading icon -->
      <%= if @status.flags[:backup] do %>
        <div>
          <.icon
            id="backUp"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <!-- Syncronization icon, like cirle arrows -->
      <%= if @status.flags[:replication] do %>
        <div class="w-[21px] pt-0.5">
          <.icon
            id="replication"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <!-- <div class="h-[27px]">
              <.icon id="car" class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}/>
            </div> -->
    </div>
    """
  end
end
