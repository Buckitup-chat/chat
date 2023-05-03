defmodule ChatWeb.MainLive.Layout.DbStatus do
  @moduledoc "DB status layout"

  import ChatWeb.LiveHelpers

  use Phoenix.Component

  def desktop(assigns) do
    ~H"""
    <div class="sidebarIcon mb-1">
      <%= if @status.mode == :internal do %>
        <!-- Crossed DB icon -->
        <div class="pb-2.5 pl-[3.25px]">
          <.icon
            id="crossedDataBase"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.mode == :main do %>
        <!-- DB icon -->
        <div class="pb-2.5 pl-[1.25px]">
          <.icon
            id="dataBase"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.mode == :internal_to_main do %>
        <!-- Blinking or transparent DB icon -->
        <div class="pb-2.5 pl-[1.25px]">
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
        <div class="pb-2.5 pl-[3.25px]">
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
        <div class="pb-1 pl-[9px]">
          <.icon
            id="backUp"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <!-- Syncronization icon, like cirle arrows -->
      <%= if @status.flags[:replication] do %>
        <div class="pl-[9px]">
          <.icon
            id="replication"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.flags[:cargo] do %>
        <div class="pb-1">
          <.icon
            id="cargo"
            class={classes("w-9 h-9 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.flags[:usb_drive_dump] do %>
        <div class="pb-1">
          <.icon
            id="usbDrive"
            class={classes("w-8 h-8 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
        <%!-- <div class="absolute inline-block bottom-16">
          <div class="overflow-hidden rounded-full w-10 h-10">
            <svg
              class="absolute top-0 left-0 w-full h-full text-gray-300 a-progress-bar"
              viewBox="0 0 44 44"
            >
              <circle
                class="fill-transparent stroke-current"
                stroke-dashoffset={
                  126 -
                    126 *
                      (get_in(assigns, [
                         Access.key!(:usb_drive_dump_room),
                         Access.key!(:progress),
                         Access.key!(:percentage)
                       ]) || 0) / 100
                }
                stroke-width="4"
                cx="22"
                cy="22"
                r="20"
              >
              </circle>
            </svg>
          </div>
        </div> --%>
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
              classes("w-5 h-[19.5px] fill-gray-500 animate-pulse", %{
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
              classes("w-5 h-[19.5px] fill-gray-500 animate-pulse", %{
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
      <%= if @status.flags[:cargo] do %>
        <div class="pb-2 pr-1">
          <.icon
            id="cargo"
            class={classes("w-8 h-8 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
      <% end %>
      <%= if @status.flags[:usb_drive_dump] do %>
        <div class="pb-2 pr-1">
          <.icon
            id="usbDrive"
            class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}
          />
        </div>
        <div class="absolute inline-block bottom-2">
          <div class="overflow-hidden rounded-full w-8 h-8">
            <svg
              class="absolute top-0 left-0 w-full h-full text-gray-300 a-progress-bar"
              viewBox="0 0 44 44"
            >
              <circle
                class="fill-transparent stroke-current"
                stroke-dashoffset={
                  126 -
                    126 *
                      (get_in(assigns, [
                         Access.key!(:usb_drive_dump_room),
                         Access.key!(:progress),
                         Access.key!(:percentage)
                       ]) || 0) / 100
                }
                stroke-width="4"
                cx="22"
                cy="22"
                r="20"
              >
              </circle>
            </svg>
          </div>
        </div>
      <% end %>
      <!-- <div class="h-[27px]">
              <.icon id="car" class={classes("w-6 h-6 fill-gray-200", %{"fill-red-600" => @status.writable == :no})}/>
            </div> -->
    </div>
    """
  end
end
