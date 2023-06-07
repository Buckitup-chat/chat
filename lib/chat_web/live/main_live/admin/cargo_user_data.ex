defmodule ChatWeb.MainLive.Admin.CargoUserData do
  @moduledoc "Cargo user info/form"
  use ChatWeb, :live_component

  alias Chat.Card
  alias ChatWeb.MainLive.Layout

  def mount(socket) do
    socket
    |> assign(:valid_input?, false)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @cargo_user do %>
        <Layout.Card.hashed_name card={Card.from_identity(@cargo_user)} />
      <% else %>
        <div class="mt-3 w-80">Create a cargo user to have access to cargo settings.</div>
        <div class="mt-3">
          <.form
            :let={f}
            for={%{}}
            as={:user}
            id="cargo_user_form"
            phx-submit="create"
            phx-target={@myself}
            phx-change="validate"
          >
            <%= text_input(f, :name,
              placeholder: "Your name",
              class:
                "w-full h-11 bg-transparent border border-gray/50 rounded-lg text-gray placeholder-gray/50 focus:outline-none focus:ring-0 focus:border-gray"
            ) %>
            <div class="mt-2.5">
              <%= submit("Create",
                phx_disable_with: "Saving...",
                class:
                  "w-full h-11 focus:outline-none text-white px-4 rounded-lg disabled:opacity-50",
                style: "background-color: rgb(36, 24, 36);",
                disabled: !@valid_input?
              ) %>
            </div>
          </.form>
        </div>
      <% end %>
    </div>
    """
  end

  def handle_event("validate", %{"user" => %{"name" => name}}, socket) do
    socket
    |> assign(:valid_input?, name |> String.trim() |> String.length() |> then(&(&1 >= 2)))
    |> noreply()
  end

  def handle_event("create", %{"user" => %{"name" => name}}, socket) do
    send(self(), {:admin, {:create_cargo_user, name}})

    socket
    |> noreply()
  end
end
