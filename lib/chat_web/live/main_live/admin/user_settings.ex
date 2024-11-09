defmodule ChatWeb.MainLive.Admin.UserSettings do
  @moduledoc """
  User settings
  """
  use ChatWeb, :live_component

  def mount(socket) do
    form =
      %{
        "skip_user_creation" => Chat.AdminDb.get(:skip_user_creation)
      }
      |> to_form()

    socket
    |> assign(form: form)
    |> ok()
  end

  def handle_event("update", %{"skip_user_creation" => skip_user_creation}, socket) do
    Chat.AdminDb.put(:skip_user_creation, skip_user_creation === "true" || nil)

    socket |> noreply()
  end

  def render(assigns) do
    ~H"""
    <section>
      <.form for={@form} phx-change="update" phx-target={@myself} data-phx-value-id="">
        <div class="flex items-center">
          <%= label do %>
            <%= checkbox(@form, "skip_user_creation") %>

            <span class="ml-2 text-sm">
              Disable new user login
            </span>
          <% end %>
        </div>
      </.form>
    </section>
    """
  end
end
